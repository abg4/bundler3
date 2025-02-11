// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {IAcrossAdapter, Offsets, MarketParams} from "../interfaces/IAcrossAdapter.sol";
import {CoreAdapter, ErrorsLib, IERC20, SafeERC20, UtilsLib} from "./CoreAdapter.sol";
import {BytesLib} from "../libraries/BytesLib.sol";

/// @custom:security-contact bugs@across.to
/// @notice Adapter for bridging with Across.
contract AcrossAdapter is CoreAdapter, IAcrossAdapter {
    using BytesLib for bytes;

    /* IMMUTABLES */

    /// @notice The address of the Across SpokePool contract.
    IAcrossAdapter public immutable SPOKE_POOL;

    /* CONSTRUCTOR */

    /// @param bundler3 The address of the Bundler3 contract.
    /// @param spokePool The address of Across SpokePool contract.
    constructor(address bundler3, address spokePool) CoreAdapter(bundler3) {
        require(spokePool != address(0), ErrorsLib.ZeroAddress());

        SPOKE_POOL = IAcrossAdapter(spokePool);
    }

    /* BRIDGE ACTIONS */

    /// @notice Bridges an exact amount or full balance using the `callData` provided.
    /// @param spokePool Address of the Across SpokePool contract.
    /// @param callData Deposit data to call Across SpokePool with.
    /// @param inputToken The token to bridge.
    /// @param bridgeEntireBalance If true, bridges the entire balance of the inputToken held by this contract.
    /// @param relayFeePercentage The Across relay fee percentage (included in Across API response).
    /// @param offsets The offsets for input and output amounts in callData.
    /// @param receiver The address leftover tokens will be sent to.
    function bridge(
        address spokePool,
        bytes memory callData,
        address inputToken,
        bool bridgeEntireBalance,
        int256 relayFeePercentage,
        Offsets calldata offsets,
        address receiver
    ) external onlyBundler3 {
        require(spokePool == address(SPOKE_POOL), "Invalid SpokePool");

        if (bridgeEntireBalance) {
            updateAmounts(callData, inputToken, offsets, relayFeePercentage);
        }

        SafeERC20.forceApprove(
            IERC20(inputToken),
            spokePool,
            type(uint256).max
        );

        (bool success, bytes memory returnData) = spokePool.call(callData);
        if (!success) UtilsLib.lowLevelRevert(returnData);

        SafeERC20.forceApprove(IERC20(inputToken), spokePool, 0);

        uint256 balance = IERC20(inputToken).balanceOf(address(this));
        if (receiver != address(this) && balance > 0) {
            SafeERC20.safeTransfer(IERC20(inputToken), receiver, balance);
        }
    }

    /// @notice Sets input and output amounts in `callData`.
    /// @param callData The calldata to modify.
    /// @param inputToken The token to bridge.
    /// @param offsets The offsets for input and output amounts in callData
    /// @param relayFeePercentage The Across relay fee percentage (included in Across API response).
    function updateAmounts(
        bytes memory callData,
        address inputToken,
        Offsets calldata offsets,
        int256 relayFeePercentage
    ) internal view {
        require(offsets.inputAmount > 0, "Input amount offset must be set");
        require(offsets.outputAmount > 0, "Output amount offset must be set");

        uint256 inputAmount = IERC20(inputToken).balanceOf(address(this));

        callData.set(offsets.inputAmount, inputAmount);

        uint256 amountAfterFees = _computeAmountPostFees(
            inputAmount,
            relayFeePercentage
        );

        callData.set(offsets.outputAmount, amountAfterFees);
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
