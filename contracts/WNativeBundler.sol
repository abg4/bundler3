// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.21;

import {IWNative} from "./interfaces/IWNative.sol";

import {Math} from "@morpho-utils/math/Math.sol";
import {ErrorsLib} from "./libraries/ErrorsLib.sol";
import {SafeTransferLib, ERC20} from "solmate/src/utils/SafeTransferLib.sol";

import {BaseBundler} from "./BaseBundler.sol";
import {Permit2Bundler} from "./Permit2Bundler.sol";

/// @title WNativeBundler
/// @author Morpho Labs
/// @custom:contact security@morpho.org
/// @notice Bundler contract managing interactions with network's wrapped native token.
abstract contract WNativeBundler is BaseBundler, Permit2Bundler {
    using SafeTransferLib for ERC20;

    /* IMMUTABLES */

    /// @dev The address of the wrapped native token contract.
    address public immutable WRAPPED_NATIVE;

    /* CONSTRUCTOR */

    constructor(address wNative) {
        require(wNative != address(0), ErrorsLib.ZERO_ADDRESS);

        WRAPPED_NATIVE = wNative;
    }

    /* CALLBACKS */

    /// @dev Only the wNative contract is allowed to transfer the native token to this contract, without any calldata.
    receive() external payable virtual {
        require(msg.sender == WRAPPED_NATIVE, ErrorsLib.ONLY_WNATIVE);
    }

    /* ACTIONS */

    /// @notice Wraps the given `amount` of the native token to wNative and transfers it to `receiver`.
    /// @notice Warning: should only be called via the bundler's `multicall` function.
    function wrapNative(uint256 amount, address receiver) external payable {
        require(receiver != address(0), ErrorsLib.ZERO_ADDRESS);

        amount = Math.min(amount, address(this).balance);

        require(amount != 0, ErrorsLib.ZERO_AMOUNT);

        IWNative(WRAPPED_NATIVE).deposit{value: amount}();

        if (receiver != address(this)) ERC20(WRAPPED_NATIVE).safeTransfer(receiver, amount);
    }

    /// @notice Unwraps the given `amount` of wNative to the native token and transfers it to `receiver`.
    /// @notice Warning: should only be called via the bundler's `multicall` function.
    function unwrapNative(uint256 amount, address receiver) external payable {
        require(receiver != address(0), ErrorsLib.ZERO_ADDRESS);

        amount = Math.min(amount, ERC20(WRAPPED_NATIVE).balanceOf(address(this)));

        require(amount != 0, ErrorsLib.ZERO_AMOUNT);

        IWNative(WRAPPED_NATIVE).withdraw(amount);

        SafeTransferLib.safeTransferETH(receiver, amount);
    }
}
