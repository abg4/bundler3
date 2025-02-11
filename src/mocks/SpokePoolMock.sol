// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {Test} from "../../lib/forge-std/src/Test.sol";

contract SpokePoolMock is Test {
    uint256 public toBridge = type(uint256).max;

    function setToBridge(uint256 amount) external {
        toBridge = amount;
    }

    function mockBridge(address srcToken, uint256 amount) external {
        require(amount > 0, "Amount must be greater than zero");

        if (toBridge != type(uint256).max) amount = toBridge;

        // Transfer tokens from the user to the contract itself
        bool success = IERC20(srcToken).transferFrom(
            msg.sender,
            address(this),
            amount
        );
        require(success, "Token transfer failed");

        // Reset toBridge to its default state
        toBridge = type(uint256).max;
    }
}
