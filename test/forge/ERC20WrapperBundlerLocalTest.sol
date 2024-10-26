// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {ErrorsLib} from "../../src/libraries/ErrorsLib.sol";

import {ERC20WrapperMock, ERC20Wrapper} from "../../src/mocks/ERC20WrapperMock.sol";

import {ERC20WrapperBundler} from "../../src/ERC20WrapperBundler.sol";
import "./helpers/LocalTest.sol";

contract ERC20WrapperBundlerLocalTest is LocalTest {
    ERC20WrapperMock internal loanWrapper;

    function setUp() public override {
        super.setUp();

        loanWrapper = new ERC20WrapperMock(loanToken, "Wrapped Loan Token", "WLT");
    }

    function testErc20WrapperDepositFor(uint256 amount) public {
        amount = bound(amount, MIN_AMOUNT, MAX_AMOUNT);

        bundle.push(_erc20WrapperDepositFor(address(loanWrapper), address(genericBundler1), amount));

        loanToken.setBalance(address(genericBundler1), amount);

        vm.prank(RECEIVER);
        hub.multicall(bundle);

        assertEq(loanToken.balanceOf(address(genericBundler1)), 0, "loan.balanceOf(genericBundler1)");
        assertEq(loanWrapper.balanceOf(RECEIVER), amount, "loanWrapper.balanceOf(RECEIVER)");
    }

    function testErc20WrapperDepositForZeroAmount() public {
        bundle.push(_erc20WrapperDepositFor(address(loanWrapper), address(genericBundler1), 0));

        vm.expectRevert(bytes(ErrorsLib.ZERO_AMOUNT));
        hub.multicall(bundle);
    }

    function testErc20WrapperWithdrawTo(uint256 amount) public {
        amount = bound(amount, MIN_AMOUNT, MAX_AMOUNT);

        loanWrapper.setBalance(address(genericBundler1), amount);
        loanToken.setBalance(address(loanWrapper), amount);

        bundle.push(_erc20WrapperWithdrawTo(address(loanWrapper), RECEIVER, amount));

        hub.multicall(bundle);

        assertEq(loanWrapper.balanceOf(address(genericBundler1)), 0, "loanWrapper.balanceOf(genericBundler1)");
        assertEq(loanToken.balanceOf(RECEIVER), amount, "loan.balanceOf(RECEIVER)");
    }

    function testErc20WrapperWithdrawToAll(uint256 amount, uint256 inputAmount) public {
        amount = bound(amount, MIN_AMOUNT, MAX_AMOUNT);
        inputAmount = bound(inputAmount, amount, type(uint256).max);

        loanWrapper.setBalance(address(genericBundler1), amount);
        loanToken.setBalance(address(loanWrapper), amount);

        bundle.push(_erc20WrapperWithdrawTo(address(loanWrapper), RECEIVER, inputAmount));

        hub.multicall(bundle);

        assertEq(loanWrapper.balanceOf(address(genericBundler1)), 0, "loanWrapper.balanceOf(genericBundler1)");
        assertEq(loanToken.balanceOf(RECEIVER), amount, "loan.balanceOf(RECEIVER)");
    }

    function testErc20WrapperWithdrawToAccountZeroAddress(uint256 amount) public {
        amount = bound(amount, MIN_AMOUNT, MAX_AMOUNT);

        bundle.push(_erc20WrapperWithdrawTo(address(loanWrapper), address(0), amount));

        vm.expectRevert(bytes(ErrorsLib.ZERO_ADDRESS));
        hub.multicall(bundle);
    }

    function testErc20WrapperWithdrawToZeroAmount() public {
        bundle.push(_erc20WrapperWithdrawTo(address(loanWrapper), RECEIVER, 0));

        vm.expectRevert(bytes(ErrorsLib.ZERO_AMOUNT));
        hub.multicall(bundle);
    }

    function testErc20WrapperDepositForUnauthorized(uint256 amount) public {
        amount = bound(amount, MIN_AMOUNT, MAX_AMOUNT);

        vm.expectRevert(bytes(ErrorsLib.UNAUTHORIZED_SENDER));
        genericBundler1.erc20WrapperDepositFor(address(loanWrapper), address(genericBundler1), amount);
    }

    function testErc20WrapperWithdrawToUnauthorized(uint256 amount) public {
        amount = bound(amount, MIN_AMOUNT, MAX_AMOUNT);

        vm.expectRevert(bytes(ErrorsLib.UNAUTHORIZED_SENDER));
        genericBundler1.erc20WrapperWithdrawTo(address(loanWrapper), RECEIVER, amount);
    }

    function testErc20WrapperDepositToFailed(uint256 amount) public {
        amount = bound(amount, MIN_AMOUNT, MAX_AMOUNT);
        loanToken.setBalance(address(genericBundler1), amount);

        bundle.push(_erc20WrapperDepositFor(address(loanWrapper), address(genericBundler1), amount));

        vm.mockCall(address(loanWrapper), abi.encodeWithSelector(ERC20Wrapper.depositFor.selector), abi.encode(false));

        vm.expectRevert(bytes(ErrorsLib.DEPOSIT_FAILED));
        hub.multicall(bundle);
    }

    function testErc20WrapperWithdrawToFailed(uint256 amount) public {
        amount = bound(amount, MIN_AMOUNT, MAX_AMOUNT);
        loanWrapper.setBalance(address(genericBundler1), amount);
        loanToken.setBalance(address(loanWrapper), amount);

        bundle.push(_erc20WrapperWithdrawTo(address(loanWrapper), RECEIVER, amount));

        vm.mockCall(address(loanWrapper), abi.encodeWithSelector(ERC20Wrapper.withdrawTo.selector), abi.encode(false));

        vm.expectRevert(bytes(ErrorsLib.WITHDRAW_FAILED));
        hub.multicall(bundle);
    }
}
