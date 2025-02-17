// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

import {MarketParams} from "../../lib/morpho-blue/src/interfaces/IMorpho.sol";

/// @notice The depositData is the data structure used to specify an Across Deposit.
struct DepositData {
    address depositor;
    address recipient;
    address inputToken;
    address outputToken;
    uint256 inputAmount;
    uint256 outputAmount;
    uint256 destinationChainid;
    address exclusiveRelayer;
    uint32 quoteTimestamp;
    uint32 fillDeadline;
    uint32 exclusivityDeadline;
    bytes message;
}

/// @custom:security-contact bugs@across.to
/// @notice Interface of Across Adapter.
interface IAcrossAdapter {
    function bridge(
        DepositData memory depositData,
        bool bridgeEntireBalance,
        int256 relayFeePercentage,
        address receiver
    ) external;
}
