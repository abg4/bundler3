// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../../WNativeBundler.sol";
import "../../TransferBundler.sol";

contract WNativeBundlerMock is WNativeBundler, TransferBundler {
    constructor(address wNative) WNativeBundler(wNative) {}
}
