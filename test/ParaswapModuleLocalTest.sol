// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {ErrorsLib} from "../src/libraries/ErrorsLib.sol";

import "./helpers/LocalTest.sol";
import {IAugustusRegistry} from "../src/interfaces/IAugustusRegistry.sol";
import {MathLib} from "../lib/morpho-blue/src/libraries/MathLib.sol";
import {EventsLib} from "../src/libraries/EventsLib.sol";

contract ParaswapModuleLocalTest is LocalTest {
    using MathLib for uint256;

    function setUp() public virtual override {
        super.setUp();
        augustus = new AugustusMock();
        augustusRegistryMock.setValid(address(augustus), true);
    }

    function _makeEmptyAccountCallable(address account) internal {
        assumeNotPrecompile(account);
        assumeNotForgeAddress(account);
        assumeNotZeroAddress(account);
        vm.assume(account != 0x000000000000000000000000000000000000000A);
        vm.assume(account.code.length == 0);
        vm.etch(account, hex"5f5ff3"); // always return null
    }

    function _receiver(address account) internal view {
        assumeNotZeroAddress(account);
        vm.assume(account != address(paraswapModule));
        vm.assume(account != address(augustus));
        vm.assume(account != address(this));
    }

    function testAugustusInRegistrySellCheck(address _augustus) public {
        augustusRegistryMock.setValid(_augustus, false);

        vm.prank(address(bundler));

        vm.expectRevert(abi.encodeWithSelector(ErrorsLib.AugustusNotInRegistry.selector, _augustus));
        paraswapModule.sell(_augustus, hex"", address(0), address(0), true, Offsets(0, 0, 0), address(0));
    }

    function testAugustusInRegistryBuyCheck(address _augustus) public {
        augustusRegistryMock.setValid(_augustus, false);

        vm.prank(address(bundler));

        vm.expectRevert(abi.encodeWithSelector(ErrorsLib.AugustusNotInRegistry.selector, _augustus));
        paraswapModule.buy(_augustus, hex"", address(0), address(0), 0, Offsets(0, 0, 0), address(0));
    }

    uint256 _bytesLength = 1024;

    function _boundOffset(uint256 offset) internal view returns (uint256) {
        return bound(offset, 0, _bytesLength - 32 * 3);
    }

    function _swapCalldata(uint256 offset, uint256 exactAmount, uint256 limitAmount, uint256 quotedAmount)
        internal
        view
        returns (bytes memory)
    {
        return bytes.concat(
            new bytes(offset),
            bytes32(exactAmount),
            bytes32(limitAmount),
            bytes32(quotedAmount),
            new bytes(_bytesLength - 32 * 3 - offset)
        );
    }

    function _updateAmountsSell(
        address _augustus,
        uint256 initialExact,
        uint256 initialLimit,
        uint256 initialQuoted,
        uint256 adjustedExact,
        uint256 offset,
        bool adjustQuoted
    ) internal {
        _makeEmptyAccountCallable(_augustus);
        augustusRegistryMock.setValid(_augustus, true);

        offset = _boundOffset(offset);

        initialExact = bound(initialExact, 1, type(uint64).max);
        initialLimit = bound(initialLimit, 0, type(uint64).max);
        initialQuoted = bound(initialQuoted, 0, type(uint64).max);
        adjustedExact = bound(adjustedExact, 0, type(uint64).max);
        uint256 adjustedLimit = initialLimit.mulDivUp(adjustedExact, initialExact);

        uint256 adjustedQuoted;
        uint256 quotedOffset;

        if (adjustQuoted) {
            adjustedQuoted = initialQuoted.mulDivUp(adjustedExact, initialExact);
            quotedOffset = offset + 64;
        } else {
            adjustedQuoted = initialQuoted;
            quotedOffset = 0;
        }

        collateralToken.setBalance(address(paraswapModule), adjustedExact);

        if (adjustedLimit > 0) {
            vm.expectPartialRevert(ErrorsLib.BuyAmountTooLow.selector);
        }
        vm.expectCall(address(_augustus), _swapCalldata(offset, adjustedExact, adjustedLimit, adjustedQuoted));
        // adjustedData);
        bundle.push(
            _call(
                paraswapModule,
                _paraswapSell(
                    _augustus,
                    _swapCalldata(offset, initialExact, initialLimit, initialQuoted),
                    address(collateralToken),
                    address(loanToken),
                    true,
                    Offsets(offset, offset + 32, quotedOffset),
                    address(1)
                )
            )
        );
        bundler.multicall(bundle);
    }

    function testUpdateAmountsSellWithQuoteUpdate(
        address _augustus,
        uint256 initialExact,
        uint256 initialLimit,
        uint256 initialQuoted,
        uint256 adjustedExact,
        uint256 offset
    ) public {
        _updateAmountsSell(_augustus, initialExact, initialLimit, initialQuoted, adjustedExact, offset, true);
    }

    function testUpdateAmountsSellNoQuoteUpdate(
        address _augustus,
        uint256 initialExact,
        uint256 initialLimit,
        uint256 initialQuoted,
        uint256 adjustedExact,
        uint256 offset
    ) public {
        _updateAmountsSell(_augustus, initialExact, initialLimit, initialQuoted, adjustedExact, offset, false);
    }

    // Checks that the module correctly adjusts amounts sent to augustus.
    // Expects a revert since the augustus address will not swap the tokens.
    function _updateAmountsBuy(
        address _augustus,
        uint256 initialExact,
        uint256 initialLimit,
        uint256 initialQuoted,
        uint256 adjustedExact,
        uint256 offset,
        bool adjustQuoted
    ) internal {
        _makeEmptyAccountCallable(_augustus);
        augustusRegistryMock.setValid(_augustus, true);

        offset = _boundOffset(offset);

        initialExact = bound(initialExact, 1, type(uint64).max);
        initialLimit = bound(initialLimit, 0, type(uint64).max);
        initialQuoted = bound(initialQuoted, 0, type(uint64).max);
        adjustedExact = bound(adjustedExact, 1, type(uint64).max);

        uint256 adjustedLimit = initialLimit.mulDivDown(adjustedExact, initialExact);

        uint256 adjustedQuoted;
        uint256 quotedOffset;
        if (adjustQuoted) {
            adjustedQuoted = initialQuoted.mulDivDown(adjustedExact, initialExact);
            quotedOffset = offset + 64;
        } else {
            adjustedQuoted = initialQuoted;
            quotedOffset = 0;
        }

        vm.expectPartialRevert(ErrorsLib.BuyAmountTooLow.selector);
        vm.expectCall(address(_augustus), _swapCalldata(offset, adjustedExact, adjustedLimit, adjustedQuoted));
        bundle.push(
            _call(
                paraswapModule,
                _paraswapBuy(
                    _augustus,
                    _swapCalldata(offset, initialExact, initialLimit, initialQuoted),
                    address(collateralToken),
                    address(loanToken),
                    adjustedExact,
                    Offsets(offset, offset + 32, quotedOffset),
                    address(1)
                )
            )
        );
        bundler.multicall(bundle);
    }

    function testUpdateAmountsBuyWithQuoteUpdate(
        address _augustus,
        uint256 initialExact,
        uint256 initialLimit,
        uint256 initialQuoted,
        uint256 adjustedExact,
        uint256 offset
    ) public {
        _updateAmountsBuy(_augustus, initialExact, initialLimit, initialQuoted, adjustedExact, offset, true);
    }

    function testUpdateAmountsBuyNoQuoteUpdate(
        address _augustus,
        uint256 initialExact,
        uint256 initialLimit,
        uint256 initialQuoted,
        uint256 adjustedExact,
        uint256 offset
    ) public {
        _updateAmountsBuy(_augustus, initialExact, initialLimit, initialQuoted, adjustedExact, offset, false);
    }

    function testBuyExactAmountCheck(uint256 amount, uint256 subAmount) public {
        amount = bound(amount, 1, type(uint64).max);
        subAmount = bound(subAmount, 0, amount - 1);

        collateralToken.setBalance(address(paraswapModule), amount);

        augustus.setToGive(subAmount);
        vm.expectRevert(abi.encodeWithSelector(ErrorsLib.BuyAmountTooLow.selector, subAmount));
        bundle.push(_buy(address(collateralToken), address(loanToken), amount, amount, 0, address(this)));
        bundler.multicall(bundle);
    }

    function testSellExactAmountCheck(uint256 amount, uint256 supAmount) public {
        amount = bound(amount, 1, type(uint64).max);
        supAmount = bound(supAmount, amount + 1, type(uint120).max);

        collateralToken.setBalance(address(paraswapModule), supAmount);

        augustus.setToTake(supAmount);
        vm.expectRevert(abi.encodeWithSelector(ErrorsLib.SellAmountTooHigh.selector, supAmount));
        bundle.push(_sell(address(collateralToken), address(loanToken), amount, amount, false, address(this)));
        bundler.multicall(bundle);
    }

    function testSwapEventSell(bytes32 salt, uint256 srcAmount, uint256 destAmount, address receiver) public {
        _receiver(receiver);
        srcAmount = bound(srcAmount, 0, type(uint128).max);
        destAmount = bound(destAmount, 0, type(uint128).max);

        augustus.setToTake(srcAmount);
        augustus.setToGive(destAmount);

        ERC20Mock srcToken = new ERC20Mock{salt: salt}("src", "SRC");
        ERC20Mock destToken = new ERC20Mock{salt: salt}("dest", "DEST");

        srcToken.setBalance(address(paraswapModule), srcAmount);

        vm.expectEmit(true, true, true, true, address(paraswapModule));
        emit EventsLib.ParaswapModuleSwap(address(srcToken), address(destToken), receiver, srcAmount, destAmount);

        bundle.push(_sell(address(srcToken), address(destToken), srcAmount, destAmount, false, receiver));
        bundler.multicall(bundle);
    }

    function testSwapEventBuy(bytes32 salt, uint256 srcAmount, uint256 destAmount, address receiver) public {
        _receiver(receiver);
        srcAmount = bound(srcAmount, 0, type(uint128).max);
        destAmount = bound(destAmount, 0, type(uint128).max);

        augustus.setToTake(srcAmount);
        augustus.setToGive(destAmount);

        ERC20Mock srcToken = new ERC20Mock{salt: salt}("src", "SRC");
        ERC20Mock destToken = new ERC20Mock{salt: salt}("dest", "DEST");

        srcToken.setBalance(address(paraswapModule), srcAmount);

        vm.expectEmit(true, true, true, true, address(paraswapModule));
        emit EventsLib.ParaswapModuleSwap(address(srcToken), address(destToken), receiver, srcAmount, destAmount);

        bundle.push(_buy(address(srcToken), address(destToken), srcAmount, destAmount, 0, receiver));
        bundler.multicall(bundle);
    }

    function testSellSlippageCheckNoAdjustment(uint256 srcAmount, uint256 adjust) public {
        srcAmount = bound(srcAmount, 1, type(uint128).max);
        adjust = bound(adjust, 1, type(uint128).max);
        uint256 minDestAmount = srcAmount + adjust;

        collateralToken.setBalance(address(paraswapModule), srcAmount);

        vm.expectRevert(abi.encodeWithSelector(ErrorsLib.BuyAmountTooLow.selector, srcAmount));
        bundle.push(_sell(address(collateralToken), address(loanToken), srcAmount, minDestAmount, false, address(this)));
        bundler.multicall(bundle);
    }

    function testBuySlippageCheckNoAdjustment(uint256 destAmount, uint256 adjust) public {
        destAmount = bound(destAmount, 1, type(uint128).max);
        adjust = bound(adjust, 1, destAmount);
        uint256 maxSrcAmount = destAmount - adjust;

        collateralToken.setBalance(address(paraswapModule), destAmount); // price is 1

        vm.expectRevert(abi.encodeWithSelector(ErrorsLib.SellAmountTooHigh.selector, destAmount));
        bundle.push(_buy(address(collateralToken), address(loanToken), maxSrcAmount, destAmount, 0, address(this)));
        bundler.multicall(bundle);
    }

    function testSellSlippageCheckWithAdjustment(uint256 srcAmount, uint256 adjust, uint256 percent) public {
        percent = bound(percent, 1, 1000);
        srcAmount = bound(srcAmount, 1, type(uint120).max);
        adjust = bound(adjust, 1, srcAmount);
        uint256 minDestAmount = srcAmount + adjust;

        collateralToken.setBalance(address(paraswapModule), srcAmount.mulDivUp(percent, 100));

        vm.expectPartialRevert(ErrorsLib.BuyAmountTooLow.selector);
        bundle.push(_sell(address(collateralToken), address(loanToken), srcAmount, minDestAmount, true, address(this)));
        bundler.multicall(bundle);
    }

    function testBuySlippageCheckWithAdjustment(uint256 destAmount, uint256 adjust, uint256 percent) public {
        percent = bound(percent, 1, 1000);
        destAmount = bound(destAmount, 1, type(uint64).max);
        adjust = bound(adjust, 1, destAmount);
        uint256 maxSrcAmount = destAmount - adjust;
        uint256 newDestAmount = destAmount.mulDivUp(percent, 100);

        collateralToken.setBalance(address(paraswapModule), type(uint128).max);

        vm.expectPartialRevert(ErrorsLib.SellAmountTooHigh.selector);
        bundle.push(
            _buy(address(collateralToken), address(loanToken), maxSrcAmount, destAmount, newDestAmount, address(this))
        );
        bundler.multicall(bundle);
    }

    function testSellNoAdjustment(uint256 amount, uint256 extra, address receiver) public {
        _receiver(receiver);

        amount = bound(amount, 1, type(uint128).max);
        extra = bound(extra, 0, type(uint128).max);

        collateralToken.setBalance(address(paraswapModule), amount + extra);
        bundle.push(_sell(address(collateralToken), address(loanToken), amount, amount, false, receiver));
        bundler.multicall(bundle);
        assertEq(collateralToken.balanceOf(receiver), extra, "receiver collateral");
        assertEq(loanToken.balanceOf(receiver), amount, "receiver loan token");
        assertEq(collateralToken.balanceOf(address(paraswapModule)), 0, "paraswap module collateral");
        assertEq(loanToken.balanceOf(address(paraswapModule)), 0, "paraswap module loan token");
    }

    function testBuyNoAdjustment(uint256 amount, uint256 extra, address receiver) public {
        _receiver(receiver);

        amount = bound(amount, 1, type(uint128).max);
        extra = bound(extra, 0, type(uint128).max);

        collateralToken.setBalance(address(paraswapModule), amount + extra);
        bundle.push(_buy(address(collateralToken), address(loanToken), amount, amount, 0, receiver));
        bundler.multicall(bundle);
        assertEq(collateralToken.balanceOf(receiver), extra, "receiver collateral");
        assertEq(loanToken.balanceOf(receiver), amount, "receiver loan token");
        assertEq(collateralToken.balanceOf(address(paraswapModule)), 0, "paraswap module collateral");
        assertEq(loanToken.balanceOf(address(paraswapModule)), 0, "paraswap module loan token");
    }

    function testSellWithAdjustment(uint256 srcAmount, uint256 percent, address receiver) public {
        _receiver(receiver);

        percent = bound(percent, 1, 1000);
        srcAmount = bound(srcAmount, 1, type(uint120).max);
        uint256 actualSrcAmount = srcAmount.mulDivUp(percent, 100);

        collateralToken.setBalance(address(paraswapModule), actualSrcAmount);
        bundle.push(_sell(address(collateralToken), address(loanToken), srcAmount, srcAmount, true, receiver));
        bundler.multicall(bundle);
        assertEq(collateralToken.balanceOf(receiver), 0, "receiver collateral");
        assertEq(loanToken.balanceOf(receiver), actualSrcAmount, "receiver loan token");
        assertEq(collateralToken.balanceOf(address(paraswapModule)), 0, "paraswap module collateral");
        assertEq(loanToken.balanceOf(address(paraswapModule)), 0, "paraswap module loan token");
    }

    function testBuyWithAdjustment(uint256 destAmount, uint256 percent, address receiver) public {
        _receiver(receiver);

        percent = bound(percent, 1, 1000);
        destAmount = bound(destAmount, 1, type(uint64).max);
        uint256 actualDestAmount = destAmount.mulDivUp(percent, 100);

        collateralToken.setBalance(address(paraswapModule), actualDestAmount);

        bundle.push(
            _buy(address(collateralToken), address(loanToken), destAmount, destAmount, actualDestAmount, receiver)
        );
        bundler.multicall(bundle);
        assertEq(collateralToken.balanceOf(receiver), 0, "receiver collateral");
        assertEq(loanToken.balanceOf(receiver), actualDestAmount, "receiver loan token");
        assertEq(collateralToken.balanceOf(address(paraswapModule)), 0, "paraswap module collateral");
        assertEq(loanToken.balanceOf(address(paraswapModule)), 0, "paraswap module loan token");
    }

    function testApprovalResetSell(uint256 amount) public {
        collateralToken.setBalance(address(paraswapModule), amount);
        bundle.push(_sell(address(collateralToken), address(loanToken), amount, amount, false, address(this)));
        bundler.multicall(bundle);
        assertEq(collateralToken.allowance(address(paraswapModule), address(augustus)), 0);
    }

    function testApprovalResetBuy(uint256 amount) public {
        collateralToken.setBalance(address(paraswapModule), amount);
        bundle.push(_buy(address(collateralToken), address(loanToken), amount, amount, 0, address(this)));
        bundler.multicall(bundle);
        assertEq(collateralToken.allowance(address(paraswapModule), address(augustus)), 0);
    }
}
