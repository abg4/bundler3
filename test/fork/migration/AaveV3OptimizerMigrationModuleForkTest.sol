// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Authorization as AaveV3OptimizerAuthorization} from "../../../src/migration/interfaces/IAaveV3Optimizer.sol";

import "../../../src/migration/AaveV3OptimizerMigrationModule.sol";

import "./helpers/MigrationForkTest.sol";

contract AaveV3OptimizerMigrationModuleForkTest is MigrationForkTest {
    using SafeTransferLib for ERC20;
    using MarketParamsLib for MarketParams;
    using MorphoLib for IMorpho;
    using MorphoBalancesLib for IMorpho;

    uint256 public constant MAX_ITERATIONS = 15;

    uint256 collateralSupplied = 10_000 ether;
    uint256 borrowed = 1 ether;

    AaveV3OptimizerMigrationModule public migrationModule;

    function setUp() public override {
        super.setUp();

        if (block.chainid != 1) return;

        _initMarket(DAI, WETH);

        vm.label(AAVE_V3_OPTIMIZER, "AaveV3Optimizer");

        migrationModule = new AaveV3OptimizerMigrationModule(address(bundler), address(AAVE_V3_OPTIMIZER));
    }

    function testAaveV3OptimizerRepayUnauthorized(uint256 amount) public onlyEthereum {
        amount = bound(amount, MIN_AMOUNT, MAX_AMOUNT);

        vm.expectPartialRevert(ErrorsLib.UnauthorizedSender.selector);
        migrationModule.aaveV3OptimizerRepay(marketParams.loanToken, amount);
    }

    function testAaveV3Optimizer3RepayZeroAmount() public onlyEthereum {
        bundle.push(_aaveV3OptimizerRepay(marketParams.loanToken, 0));

        vm.expectRevert(ErrorsLib.ZeroAmount.selector);
        bundler.multicall(bundle);
    }

    function testAaveV3OtimizerAuthorizationWithSigRevert(uint256 privateKey, address owner) public onlyEthereum {
        address user;
        (privateKey, user) = _boundPrivateKey(privateKey);

        vm.assume(owner != user);

        bytes32 digest = SigUtils.toTypedDataHash(
            IAaveV3Optimizer(AAVE_V3_OPTIMIZER).DOMAIN_SEPARATOR(),
            AaveV3OptimizerAuthorization(owner, address(this), true, 0, SIGNATURE_DEADLINE)
        );

        Signature memory sig;
        (sig.v, sig.r, sig.s) = vm.sign(privateKey, digest);

        bundle.push(
            _call(
                migrationModule,
                abi.encodeCall(
                    migrationModule.aaveV3OptimizerApproveManagerWithSig, (true, 0, SIGNATURE_DEADLINE, sig, false)
                )
            )
        );

        vm.prank(user);
        vm.expectRevert(IAaveV3Optimizer.InvalidSignatory.selector);
        bundler.multicall(bundle);
    }

    function testMigrateBorrowerWithOptimizerPermit(uint256 privateKey) public onlyEthereum {
        address user;
        (privateKey, user) = _boundPrivateKey(privateKey);

        _provideLiquidity(borrowed);

        deal(marketParams.collateralToken, user, collateralSupplied + 1);

        vm.startPrank(user);
        ERC20(marketParams.collateralToken).safeApprove(AAVE_V3_OPTIMIZER, collateralSupplied + 1);
        IAaveV3Optimizer(AAVE_V3_OPTIMIZER).supplyCollateral(marketParams.collateralToken, collateralSupplied + 1, user);
        IAaveV3Optimizer(AAVE_V3_OPTIMIZER).borrow(marketParams.loanToken, borrowed, user, user, MAX_ITERATIONS);
        vm.stopPrank();

        callbackBundle.push(_morphoSetAuthorizationWithSig(privateKey, true, 0, false));
        callbackBundle.push(_morphoBorrow(marketParams, borrowed, 0, type(uint256).max, address(migrationModule)));
        callbackBundle.push(_morphoSetAuthorizationWithSig(privateKey, false, 1, false));
        callbackBundle.push(_aaveV3OptimizerRepay(marketParams.loanToken, borrowed / 2));
        callbackBundle.push(_aaveV3OptimizerRepay(marketParams.loanToken, type(uint256).max));
        callbackBundle.push(_aaveV3OptimizerApproveManager(privateKey, address(migrationModule), true, 0, false));
        callbackBundle.push(
            _aaveV3OptimizerWithdrawCollateral(
                marketParams.collateralToken, collateralSupplied, address(genericModule1)
            )
        );
        callbackBundle.push(_aaveV3OptimizerApproveManager(privateKey, address(migrationModule), false, 1, false));

        bundle.push(_morphoSupplyCollateral(marketParams, collateralSupplied, user, abi.encode(callbackBundle)));

        vm.prank(user);
        bundler.multicall(bundle);

        _assertBorrowerPosition(collateralSupplied, borrowed, user, address(genericModule1));
    }

    function testMigrateUSDTBorrowerWithOptimizerPermit(uint256 privateKey) public onlyEthereum {
        address user;
        (privateKey, user) = _boundPrivateKey(privateKey);

        uint256 amountUsdt = collateralSupplied / 1e10;

        _initMarket(USDT, WETH);
        oracle.setPrice(1e46);

        _provideLiquidity(borrowed);

        deal(USDT, user, amountUsdt + 1);

        vm.startPrank(user);
        ERC20(USDT).safeApprove(AAVE_V3_OPTIMIZER, amountUsdt + 1);
        IAaveV3Optimizer(AAVE_V3_OPTIMIZER).supplyCollateral(USDT, amountUsdt + 1, user);
        IAaveV3Optimizer(AAVE_V3_OPTIMIZER).borrow(marketParams.loanToken, borrowed, user, user, MAX_ITERATIONS);
        vm.stopPrank();

        callbackBundle.push(_morphoSetAuthorizationWithSig(privateKey, true, 0, false));
        callbackBundle.push(_morphoBorrow(marketParams, borrowed, 0, type(uint256).max, address(migrationModule)));
        callbackBundle.push(_morphoSetAuthorizationWithSig(privateKey, false, 1, false));
        callbackBundle.push(_aaveV3OptimizerRepay(marketParams.loanToken, borrowed / 2));
        callbackBundle.push(_aaveV3OptimizerRepay(marketParams.loanToken, type(uint256).max));
        callbackBundle.push(_aaveV3OptimizerApproveManager(privateKey, address(migrationModule), true, 0, false));
        callbackBundle.push(_aaveV3OptimizerWithdrawCollateral(USDT, amountUsdt, address(genericModule1)));
        callbackBundle.push(_aaveV3OptimizerApproveManager(privateKey, address(migrationModule), false, 1, false));

        bundle.push(_morphoSupplyCollateral(marketParams, amountUsdt, user, abi.encode(callbackBundle)));

        vm.prank(user);
        bundler.multicall(bundle);

        _assertBorrowerPosition(amountUsdt, borrowed, user, address(genericModule1));
    }

    function testMigrateSupplierWithOptimizerPermit(uint256 privateKey, uint256 supplied) public onlyEthereum {
        address user;
        (privateKey, user) = _boundPrivateKey(privateKey);
        supplied = bound(supplied, 100, 100 ether);

        deal(marketParams.loanToken, user, supplied + 1);

        vm.startPrank(user);
        ERC20(marketParams.loanToken).safeApprove(AAVE_V3_OPTIMIZER, supplied + 1);
        IAaveV3Optimizer(AAVE_V3_OPTIMIZER).supply(marketParams.loanToken, supplied + 1, user, MAX_ITERATIONS);
        vm.stopPrank();

        bundle.push(_aaveV3OptimizerApproveManager(privateKey, address(migrationModule), true, 0, false));
        bundle.push(_aaveV3OptimizerWithdraw(marketParams.loanToken, supplied, address(genericModule1)));
        bundle.push(_aaveV3OptimizerApproveManager(privateKey, address(migrationModule), false, 1, false));
        bundle.push(_morphoSupply(marketParams, supplied, 0, 0, user, hex""));

        vm.prank(user);
        bundler.multicall(bundle);

        _assertSupplierPosition(supplied, user, address(genericModule1));
    }

    function testMigrateSupplierToVaultWithOptimizerPermit(uint256 privateKey, uint256 supplied) public onlyEthereum {
        address user;
        (privateKey, user) = _boundPrivateKey(privateKey);
        supplied = bound(supplied, 100, 100 ether);

        deal(marketParams.loanToken, user, supplied + 1);

        vm.startPrank(user);
        ERC20(marketParams.loanToken).safeApprove(AAVE_V3_OPTIMIZER, supplied + 1);
        IAaveV3Optimizer(AAVE_V3_OPTIMIZER).supply(marketParams.loanToken, supplied + 1, user, MAX_ITERATIONS);
        vm.stopPrank();

        bundle.push(_aaveV3OptimizerApproveManager(privateKey, address(migrationModule), true, 0, false));
        bundle.push(_aaveV3OptimizerWithdraw(marketParams.loanToken, supplied, address(genericModule1)));
        bundle.push(_aaveV3OptimizerApproveManager(privateKey, address(migrationModule), false, 1, false));
        bundle.push(_erc4626Deposit(address(suppliersVault), supplied, 0, user));

        vm.prank(user);
        bundler.multicall(bundle);

        _assertVaultSupplierPosition(supplied, user, address(genericModule1));
    }

    function testAaveV3OptimizerApproveManagerUnauthorized(uint256 amount) public onlyEthereum {
        amount = bound(amount, MIN_AMOUNT, MAX_AMOUNT);

        Signature memory sig;

        vm.expectPartialRevert(ErrorsLib.UnauthorizedSender.selector);
        migrationModule.aaveV3OptimizerApproveManagerWithSig(true, 0, SIGNATURE_DEADLINE, sig, false);
    }

    function testAaveV3OptimizerWithdrawUnauthorized(uint256 amount) public onlyEthereum {
        amount = bound(amount, MIN_AMOUNT, MAX_AMOUNT);

        vm.expectPartialRevert(ErrorsLib.UnauthorizedSender.selector);
        migrationModule.aaveV3OptimizerWithdraw(marketParams.loanToken, amount, MAX_ITERATIONS, address(this));
    }

    function testAaveV3OptimizerWithdrawCollateralUnauthorized(uint256 amount) public onlyEthereum {
        amount = bound(amount, MIN_AMOUNT, MAX_AMOUNT);

        vm.expectPartialRevert(ErrorsLib.UnauthorizedSender.selector);
        migrationModule.aaveV3OptimizerWithdrawCollateral(marketParams.loanToken, amount, address(this));
    }

    /* ACTIONS */

    function _aaveV3OptimizerApproveManager(
        uint256 privateKey,
        address manager,
        bool isAllowed,
        uint256 nonce,
        bool skipRevert
    ) internal view returns (Call memory) {
        bytes32 digest = SigUtils.toTypedDataHash(
            IAaveV3Optimizer(AAVE_V3_OPTIMIZER).DOMAIN_SEPARATOR(),
            AaveV3OptimizerAuthorization(vm.addr(privateKey), manager, isAllowed, nonce, SIGNATURE_DEADLINE)
        );

        Signature memory sig;
        (sig.v, sig.r, sig.s) = vm.sign(privateKey, digest);

        return _call(
            migrationModule,
            abi.encodeCall(
                migrationModule.aaveV3OptimizerApproveManagerWithSig,
                (isAllowed, nonce, SIGNATURE_DEADLINE, sig, skipRevert)
            )
        );
    }

    function _aaveV3OptimizerRepay(address underlying, uint256 amount) internal view returns (Call memory) {
        return _call(migrationModule, abi.encodeCall(migrationModule.aaveV3OptimizerRepay, (underlying, amount)));
    }

    function _aaveV3OptimizerWithdraw(address underlying, uint256 amount, address receiver)
        internal
        view
        returns (Call memory)
    {
        return _call(
            migrationModule,
            abi.encodeCall(migrationModule.aaveV3OptimizerWithdraw, (underlying, amount, MAX_ITERATIONS, receiver))
        );
    }

    function _aaveV3OptimizerWithdrawCollateral(address underlying, uint256 amount, address receiver)
        internal
        view
        returns (Call memory)
    {
        return _call(
            migrationModule,
            abi.encodeCall(migrationModule.aaveV3OptimizerWithdrawCollateral, (underlying, amount, receiver))
        );
    }
}
