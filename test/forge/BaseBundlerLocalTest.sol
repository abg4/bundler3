// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {ErrorsLib} from "src/libraries/ErrorsLib.sol";

import "src/mocks/bundlers/CoreBundlerMock.sol";

import "./helpers/LocalTest.sol";

contract CoreBundlerLocalTest is LocalTest {
    function setUp() public override {
        super.setUp();

        bundler = new CoreBundlerMock();
    }

    function testMulticallEmpty() public {
        bundler.multicall(bundle);
    }

    function testNestedMulticall() public {
        bundle.push(abi.encodeCall(CoreBundler.multicall, (callbackBundle)));

        vm.expectRevert(bytes(ErrorsLib.ALREADY_INITIATED));
        bundler.multicall(bundle);
    }
}
