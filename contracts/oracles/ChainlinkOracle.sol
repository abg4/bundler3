// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {BaseOracle} from "./BaseOracle.sol";
import {StaticBorrowableAdapter} from "./adapters/StaticBorrowableAdapter.sol";
import {ChainlinkCollateralAdapter} from "./adapters/ChainlinkCollateralAdapter.sol";

contract ChainlinkOracle is BaseOracle, ChainlinkCollateralAdapter, StaticBorrowableAdapter {
    constructor(uint256 scaleFactor, address feed) BaseOracle(scaleFactor) ChainlinkCollateralAdapter(feed) {}
}
