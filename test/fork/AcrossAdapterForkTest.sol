// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {IAllowanceTransfer} from "../../lib/permit2/src/interfaces/IAllowanceTransfer.sol";
import {MockERC20} from "../../lib/permit2/test/mocks/MockERC20.sol";
import {BytesLib} from "../../src/libraries/BytesLib.sol";
import {Math} from "../../lib/openzeppelin-contracts/contracts/utils/math/Math.sol";

import "./helpers/ForkTest.sol";

contract AcrossAdapterForkTest is ForkTest {
    address internal SPOKE_POOL = getAddress("SPOKE_POOL");
    address internal USDC = getAddress("USDC");

    int256 relayFeePercentage = 99878000000000;
    uint32 quoteTimestamp;
    uint32 fillDeadline;

    function setUp() public override {
        // block.chainid is only available after super.setUp
        if (config.chainid != 1) return;

        config.blockNumber = 21867612;
        super.setUp();

        // Initialize quoteTimestamp and fillDeadline
        quoteTimestamp = uint32(block.timestamp);
        fillDeadline = uint32(quoteTimestamp + 2 hours);
    }

    function createDepositData(
        address user,
        uint256 inputAmount,
        uint256 outputAmount
    ) internal view returns (DepositData memory) {
        return
            DepositData({
                depositor: user,
                recipient: user,
                inputToken: USDC,
                outputToken: USDC,
                inputAmount: inputAmount,
                outputAmount: outputAmount,
                destinationChainid: 8453,
                exclusiveRelayer: address(0),
                quoteTimestamp: quoteTimestamp,
                fillDeadline: fillDeadline,
                exclusivityDeadline: 0,
                message: hex""
            });
    }

    function testBridgeDepositWithExactAmount() public onlyEthereum {
        address user = makeAddr("Test User");
        address receiver = makeAddr("Test Receiver");

        uint256 initialBalance = 100e6;
        uint256 bridgeAmount = 50e6;
        uint256 expectedOutputAmount = 49e6;

        DepositData memory depositData = createDepositData(
            user,
            bridgeAmount,
            expectedOutputAmount
        );

        deal(USDC, user, initialBalance);

        bundle.push(
            _erc20TransferFrom(USDC, address(acrossAdapter), initialBalance)
        );

        bundle.push(
            _call(acrossAdapter, _acrossBridge(depositData, false, 0, receiver))
        );

        uint256 initialSpokePoolBalance = IERC20(USDC).balanceOf(
            address(SPOKE_POOL)
        );

        vm.startPrank(user);
        IERC20(USDC).approve(address(generalAdapter1), type(uint256).max);
        bundler3.multicall(bundle);
        vm.stopPrank();

        uint256 bridged = IERC20(USDC).balanceOf(address(SPOKE_POOL)) -
            initialSpokePoolBalance;
        assertEq(bridged, bridgeAmount, "bridged");
        assertEq(
            IERC20(USDC).balanceOf(receiver),
            initialBalance - bridgeAmount,
            "receiver balance"
        );
    }

    function testBridgeDepositWithFullAmount() public onlyEthereum {
        address user = makeAddr("Test User");
        address receiver = makeAddr("Test Receiver");

        uint256 initialBalance = 150e6;
        uint256 bridgeAmount = 100e6; // intentionally different from initialBalance to test full amount
        uint256 expectedOutputAmount = 99e6;

        DepositData memory depositData = createDepositData(
            user,
            bridgeAmount,
            expectedOutputAmount
        );

        deal(USDC, user, initialBalance);

        bundle.push(
            _erc20TransferFrom(USDC, address(acrossAdapter), type(uint256).max)
        );

        bundle.push(
            _call(
                acrossAdapter,
                _acrossBridge(depositData, true, relayFeePercentage, user)
            )
        );

        uint256 initialSpokePoolBalance = IERC20(USDC).balanceOf(
            address(SPOKE_POOL)
        );

        vm.startPrank(user);
        IERC20(USDC).approve(address(generalAdapter1), type(uint256).max);

        bundler3.multicall(bundle);
        vm.stopPrank();

        uint256 bridged = IERC20(USDC).balanceOf(address(SPOKE_POOL)) -
            initialSpokePoolBalance;
        assertEq(bridged, initialBalance, "bridged");
        assertEq(IERC20(USDC).balanceOf(receiver), 0, "receiver balance");
    }

    function testWithdrawAndBridge() public onlyEthereum {
        address user = makeAddr("Test User");
        uint256 initialBalance = 100e6;
        uint256 bridgeAmount = 50e6;
        uint256 expectedOutputAmount = 49e6;
        uint256 withdrawAmount = 60e6;

        DepositData memory depositData = createDepositData(
            user,
            bridgeAmount, // intentionally different from initialBalance to test full amount
            expectedOutputAmount
        );

        MarketParams memory usdcMarketParams = MarketParams({
            collateralToken: USDC,
            loanToken: USDC,
            oracle: address(oracle),
            irm: address(irm),
            lltv: 0.8 ether
        });
        morpho.createMarket(usdcMarketParams);

        deal(USDC, user, initialBalance);

        bundle.push(_erc20TransferFrom(USDC, initialBalance));

        bundle.push(
            _morphoSupplyCollateral(
                usdcMarketParams,
                initialBalance,
                user,
                hex""
            )
        );

        bundle.push(
            _morphoWithdrawCollateral(
                usdcMarketParams,
                withdrawAmount,
                address(acrossAdapter)
            )
        );

        bundle.push(
            _call(
                acrossAdapter,
                _acrossBridge(depositData, true, relayFeePercentage, user)
            )
        );

        uint256 initialSpokePoolBalance = IERC20(USDC).balanceOf(
            address(SPOKE_POOL)
        );
        uint256 initialMorphoBalance = IERC20(USDC).balanceOf(address(morpho));

        vm.startPrank(user);
        IERC20(USDC).approve(address(generalAdapter1), type(uint256).max);

        morpho.setAuthorization(address(generalAdapter1), true);

        bundler3.multicall(bundle);
        vm.stopPrank();

        uint256 supplied = IERC20(USDC).balanceOf(address(morpho)) -
            initialMorphoBalance;
        uint256 bridged = IERC20(USDC).balanceOf(address(SPOKE_POOL)) -
            initialSpokePoolBalance;
        assertEq(bridged, withdrawAmount, "bridged");
        assertEq(supplied, initialBalance - withdrawAmount, "supplied");
    }
}
