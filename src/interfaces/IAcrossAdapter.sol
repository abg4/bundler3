// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

import {MarketParams} from "../../lib/morpho-blue/src/interfaces/IMorpho.sol";

/// @notice The offsets are:
///  - inputAmount, the offset in spokePool calldata of the input amount to bridge.
///  - outputAmount, the offset in spokePool calldata of the ouput amount to receive.
struct Offsets {
    uint256 inputAmount;
    uint256 outputAmount;
}

/// @custom:security-contact bugs@across.to
/// @notice Interface of Across Adapter.
interface IAcrossAdapter {
    function bridge(
        address spokePool,
        bytes memory callData,
        address inputToken,
        bool bridgeEntireBalance,
        int256 relayFeePercentage,
        Offsets calldata offsets,
        address receiver
    ) external;
}
