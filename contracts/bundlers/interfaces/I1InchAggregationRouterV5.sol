// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

interface I1InchAggregationRouterV5 {
    struct SwapDescription {
        address srcToken;
        address dstToken;
        address srcReceiver;
        address dstReceiver;
        uint256 amount;
        uint256 minReturnAmount;
        uint256 flags;
    }

    function swap(address executor, SwapDescription calldata desc, bytes calldata permit, bytes calldata data)
        external;
}
