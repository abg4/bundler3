// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {IAcrossAdapter, DepositData} from "../interfaces/IAcrossAdapter.sol";
import {ISpokePool} from "../interfaces/ISpokePool.sol";
import {CoreAdapter, ErrorsLib, IERC20, SafeERC20, UtilsLib} from "./CoreAdapter.sol";

/// @custom:security-contact bugs@across.to
/// @notice Adapter for bridging with Across.
contract AcrossAdapter is CoreAdapter, IAcrossAdapter {
    /* IMMUTABLES */

    /// @notice The address of the Across SpokePool contract.
    ISpokePool public immutable SPOKE_POOL;

    /* CONSTRUCTOR */

    /// @param bundler3 The address of the Bundler3 contract.
    /// @param spokePool The address of Across SpokePool contract.
    constructor(address bundler3, address spokePool) CoreAdapter(bundler3) {
        require(spokePool != address(0), ErrorsLib.ZeroAddress());

        SPOKE_POOL = ISpokePool(spokePool);
    }

    /* BRIDGE ACTIONS */

    /// @notice Bridges an exact amount or full balance using the `depositData` provided.
    /// @param depositData Deposit data to call Across SpokePool with.
    /// @param bridgeEntireBalance If true, bridges the entire balance of the inputToken held by this contract.
    /// @param relayFeePercentage The Across relay fee percentage (included in Across API response).
    /// @param receiver The address leftover tokens will be sent to.
    function bridge(
        DepositData memory depositData,
        bool bridgeEntireBalance,
        int256 relayFeePercentage,
        address receiver
    ) external onlyBundler3 {
        if (bridgeEntireBalance) {
            updateAmounts(depositData, relayFeePercentage);
        }

        SafeERC20.forceApprove(
            IERC20(depositData.inputToken),
            address(SPOKE_POOL),
            type(uint256).max
        );

        SPOKE_POOL.depositV3(
            depositData.depositor,
            depositData.recipient,
            depositData.inputToken,
            depositData.outputToken,
            depositData.inputAmount,
            depositData.outputAmount,
            depositData.destinationChainid,
            depositData.exclusiveRelayer,
            depositData.quoteTimestamp,
            depositData.fillDeadline,
            depositData.exclusivityDeadline,
            depositData.message
        );

        SafeERC20.forceApprove(
            IERC20(depositData.inputToken),
            address(SPOKE_POOL),
            0
        );

        uint256 balance = IERC20(depositData.inputToken).balanceOf(
            address(this)
        );
        if (receiver != address(this) && balance > 0) {
            SafeERC20.safeTransfer(
                IERC20(depositData.inputToken),
                receiver,
                balance
            );
        }
    }

    /// @notice Sets input and output amounts in `depositData`.
    /// @param depositData The deposit data to modify.
    /// @param relayFeePercentage The Across relay fee percentage (included in Across API response).
    function updateAmounts(
        DepositData memory depositData,
        int256 relayFeePercentage
    ) internal view {
        uint256 inputAmount = IERC20(depositData.inputToken).balanceOf(
            address(this)
        );

        depositData.inputAmount = inputAmount;

        uint256 amountAfterFees = _computeAmountPostFees(
            inputAmount,
            relayFeePercentage
        );

        depositData.outputAmount = amountAfterFees;
    }

    /// @notice Computes the output amount based on input amount and relay fee percentage.
    /// @param amount The input amount.
    /// @param relayFeePercentage The Across relay fee percentage (included in Across API response).
    function _computeAmountPostFees(
        uint256 amount,
        int256 relayFeePercentage
    ) private pure returns (uint256) {
        return (amount * uint256(int256(1e18) - relayFeePercentage)) / 1e18;
    }
}
