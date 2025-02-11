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

    function setUp() public override {
        // block.chainid is only available after super.setUp
        if (config.chainid != 1) return;

        config.blockNumber = 21811519;
        super.setUp();
    }

    // depositV3 - 50 USDC bridge deposit
    bytes _bridgeCalldata =
        hex"7b939232000000000000000000000000b8034521bb1a343d556e5005680b3f17ffc74bed000000000000000000000000b8034521bb1a343d556e5005680b3f17ffc74bed000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48000000000000000000000000833589fcd6edb6e08f4c7c32d4f71b54bda029130000000000000000000000000000000000000000000000000000000002faf0800000000000000000000000000000000000000000000000000000000002fad7d20000000000000000000000000000000000000000000000000000000000002105000000000000000000000000b96b74874126a787720a464eab3fbd2f35a5d14e0000000000000000000000000000000000000000000000000000000067a916530000000000000000000000000000000000000000000000000000000067a945190000000000000000000000000000000000000000000000000000000067a9176d000000000000000000000000000000000000000000000000000000000000018000000000000000000000000000000000000000000000000000000000000000001dc0de0000";
    uint256 inputAmountOffset = 132;
    uint256 outputAmountOffset = 164;
    int256 relayFeePercentage = 99878000000000;

    function testBridgeDepositWithExactAmount() public onlyEthereum {
        address user = makeAddr("Test User");
        address receiver = makeAddr("Test Receiver");

        uint256 initialBalance = 100e6;
        uint256 bridgeAmount = 50e6;

        deal(USDC, user, initialBalance);

        bundle.push(
            _erc20TransferFrom(USDC, address(acrossAdapter), initialBalance)
        );

        bundle.push(
            _call(
                acrossAdapter,
                _acrossBridge(
                    SPOKE_POOL,
                    _bridgeCalldata,
                    USDC,
                    false,
                    0,
                    AcrossOffsets(inputAmountOffset, outputAmountOffset),
                    receiver
                )
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
        assertEq(bridged, bridgeAmount, "bridged");
        assertEq(IERC20(USDC).balanceOf(receiver), initialBalance - bridgeAmount, "receiver balance");
    }

    function testBridgeDepositWithFullAmount() public onlyEthereum {
        address user = makeAddr("Test User");
        address receiver = makeAddr("Test Receiver");

        uint256 initialBalance = 150e6;

        deal(USDC, user, initialBalance);

        bundle.push(
            _erc20TransferFrom(USDC, address(acrossAdapter), type(uint256).max)
        );

        bundle.push(
            _call(
                acrossAdapter,
                _acrossBridge(
                    SPOKE_POOL,
                    _bridgeCalldata,
                    USDC,
                    true,
                    relayFeePercentage,
                    AcrossOffsets(inputAmountOffset, outputAmountOffset),
                    user
                )
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
        uint256 withdrawAmount = 60e6;

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
                _acrossBridge(
                    SPOKE_POOL,
                    _bridgeCalldata,
                    USDC,
                    true,
                    relayFeePercentage,
                    AcrossOffsets(inputAmountOffset, outputAmountOffset),
                    user
                )
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
