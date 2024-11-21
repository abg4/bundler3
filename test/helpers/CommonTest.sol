// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {
    IMorpho,
    Id,
    MarketParams,
    Authorization as MorphoBlueAuthorization,
    Signature as MorphoBlueSignature
} from "../../lib/morpho-blue/src/interfaces/IMorpho.sol";
import {IPublicAllocatorBase} from "../../lib/public-allocator/src/interfaces/IPublicAllocator.sol";

import {SigUtils} from "./SigUtils.sol";
import {MarketParamsLib} from "../../lib/morpho-blue/src/libraries/MarketParamsLib.sol";
import {SharesMathLib} from "../../lib/morpho-blue/src/libraries/SharesMathLib.sol";
import {MathLib, WAD} from "../../lib/morpho-blue/src/libraries/MathLib.sol";
import {UtilsLib} from "../../lib/morpho-blue/src/libraries/UtilsLib.sol";
import {SafeTransferLib, ERC20} from "../../lib/solmate/src/utils/SafeTransferLib.sol";
import {MorphoLib} from "../../lib/morpho-blue/src/libraries/periphery/MorphoLib.sol";
import {MorphoBalancesLib} from "../../lib/morpho-blue/src/libraries/periphery/MorphoBalancesLib.sol";
import {
    LIQUIDATION_CURSOR,
    MAX_LIQUIDATION_INCENTIVE_FACTOR,
    ORACLE_PRICE_SCALE
} from "../../lib/morpho-blue/src/libraries/ConstantsLib.sol";

import {IrmMock} from "../../lib/morpho-blue/src/mocks/IrmMock.sol";
import {OracleMock} from "../../lib/morpho-blue/src/mocks/OracleMock.sol";
import {WETH} from "../../lib/solmate/src/tokens/WETH.sol";
import {IParaswapModule, Offsets} from "../../src/interfaces/IParaswapModule.sol";
import {ParaswapModule} from "../../src/ParaswapModule.sol";

import {BaseModule} from "../../src/BaseModule.sol";
import {FunctionMocker} from "./FunctionMocker.sol";
import {GenericModule1, Withdrawal} from "../../src/GenericModule1.sol";
import {Bundler} from "../../src/Bundler.sol";
import {Call} from "../../src/interfaces/Call.sol";

import {AugustusRegistryMock} from "../../src/mocks/AugustusRegistryMock.sol";
import {AugustusMock} from "../../src/mocks/AugustusMock.sol";

import "../../lib/forge-std/src/Test.sol";
import "../../lib/forge-std/src/console2.sol";

uint256 constant MIN_AMOUNT = 1000;
uint256 constant MAX_AMOUNT = 2 ** 64; // Must be less than or equal to type(uint160).max.
uint256 constant SIGNATURE_DEADLINE = type(uint32).max;

abstract contract CommonTest is Test {
    using MathLib for uint256;
    using SharesMathLib for uint256;
    using MarketParamsLib for MarketParams;
    using SafeTransferLib for ERC20;
    using stdJson for string;

    address internal USER = makeAddr("User");
    address internal SUPPLIER = makeAddr("Owner");
    address internal OWNER = makeAddr("Supplier");
    address internal RECEIVER = makeAddr("Receiver");
    address internal LIQUIDATOR = makeAddr("Liquidator");

    IMorpho internal morpho;
    IrmMock internal irm;
    OracleMock internal oracle;

    Bundler internal bundler;
    GenericModule1 internal genericModule1;

    ParaswapModule paraswapModule;

    AugustusRegistryMock augustusRegistryMock;
    AugustusMock augustus;

    Call[] internal bundle;
    Call[] internal callbackBundle;

    FunctionMocker functionMocker;

    function setUp() public virtual {
        morpho = IMorpho(deployCode("Morpho.sol", abi.encode(OWNER)));
        vm.label(address(morpho), "Morpho");

        augustusRegistryMock = new AugustusRegistryMock();
        functionMocker = new FunctionMocker();

        bundler = new Bundler();
        genericModule1 = new GenericModule1(address(bundler), address(morpho), address(new WETH()));
        paraswapModule = new ParaswapModule(address(bundler), address(morpho), address(augustusRegistryMock));

        irm = new IrmMock();

        vm.startPrank(OWNER);
        morpho.enableIrm(address(irm));
        morpho.enableIrm(address(0));
        morpho.enableLltv(0);
        vm.stopPrank();

        oracle = new OracleMock();
        oracle.setPrice(ORACLE_PRICE_SCALE);

        vm.prank(USER);
        // So tests can borrow/withdraw on behalf of USER without pranking it.
        morpho.setAuthorization(address(this), true);
    }

    function emptyMarketParams() internal pure returns (MarketParams memory _emptyMarketParams) {}

    function _boundPrivateKey(uint256 privateKey) internal returns (uint256, address) {
        privateKey = bound(privateKey, 1, type(uint160).max);

        address user = vm.addr(privateKey);
        vm.label(user, "User");

        return (privateKey, user);
    }

    function _supplyCollateral(MarketParams memory _marketParams, uint256 amount, address onBehalf) internal {
        deal(_marketParams.collateralToken, onBehalf, amount, true);
        vm.prank(onBehalf);
        morpho.supplyCollateral(_marketParams, amount, onBehalf, hex"");
    }

    function _supply(MarketParams memory _marketParams, uint256 amount, address onBehalf) internal {
        deal(_marketParams.loanToken, onBehalf, amount, true);
        vm.prank(onBehalf);
        morpho.supply(_marketParams, amount, 0, onBehalf, hex"");
    }

    function _borrow(MarketParams memory _marketParams, uint256 amount, address onBehalf) internal {
        vm.prank(onBehalf);
        morpho.borrow(_marketParams, amount, 0, onBehalf, onBehalf);
    }

    function _delegatePrank(address target, bytes memory callData) internal {
        vm.mockFunction(target, address(functionMocker), callData);
        (bool success,) = target.call(callData);
        require(success, "Function mocker call failed");
    }

    /* GENERIC MODULE CALL */
    function _call(BaseModule module, bytes memory data) internal pure returns (Call memory) {
        return _call(module, data, 0);
    }

    function _call(BaseModule module, bytes memory data, uint256 value) internal pure returns (Call memory) {
        require(address(module) != address(0), "Module address is zero");
        return Call({to: address(module), data: data, value: value});
    }

    /* TRANSFER */

    function _nativeTransfer(address recipient, uint256 amount, BaseModule module)
        internal
        pure
        returns (Call memory)
    {
        return _call(module, abi.encodeCall(module.nativeTransfer, (recipient, amount)), amount);
    }

    function _nativeTransferNoFunding(address recipient, uint256 amount, BaseModule module)
        internal
        pure
        returns (Call memory)
    {
        return _call(module, abi.encodeCall(module.nativeTransfer, (recipient, amount)), 0);
    }

    /* ERC20 ACTIONS */

    function _erc20Transfer(address token, address recipient, uint256 amount, BaseModule module)
        internal
        pure
        returns (Call memory)
    {
        return _call(module, abi.encodeCall(module.erc20Transfer, (token, recipient, amount)));
    }

    function _erc20TransferFrom(address token, address recipient, uint256 amount) internal view returns (Call memory) {
        return _call(genericModule1, abi.encodeCall(GenericModule1.erc20TransferFrom, (token, recipient, amount)));
    }

    function _erc20TransferFrom(address token, uint256 amount) internal view returns (Call memory) {
        return _erc20TransferFrom(token, address(genericModule1), amount);
    }

    /* ERC20 WRAPPER ACTIONS */

    function _erc20WrapperDepositFor(address token, address receiver, uint256 amount)
        internal
        view
        returns (Call memory)
    {
        return _call(genericModule1, abi.encodeCall(GenericModule1.erc20WrapperDepositFor, (token, receiver, amount)));
    }

    function _erc20WrapperWithdrawTo(address token, address receiver, uint256 amount)
        internal
        view
        returns (Call memory)
    {
        return _call(genericModule1, abi.encodeCall(GenericModule1.erc20WrapperWithdrawTo, (token, receiver, amount)));
    }

    /* ERC4626 ACTIONS */

    function _erc4626Mint(address vault, uint256 shares, uint256 maxAssets, address receiver)
        internal
        view
        returns (Call memory)
    {
        return _call(genericModule1, abi.encodeCall(GenericModule1.erc4626Mint, (vault, shares, maxAssets, receiver)));
    }

    function _erc4626Deposit(address vault, uint256 assets, uint256 minShares, address receiver)
        internal
        view
        returns (Call memory)
    {
        return
            _call(genericModule1, abi.encodeCall(GenericModule1.erc4626Deposit, (vault, assets, minShares, receiver)));
    }

    function _erc4626Withdraw(address vault, uint256 assets, uint256 maxShares, address receiver, address owner)
        internal
        view
        returns (Call memory)
    {
        return _call(
            genericModule1, abi.encodeCall(GenericModule1.erc4626Withdraw, (vault, assets, maxShares, receiver, owner))
        );
    }

    function _erc4626Redeem(address vault, uint256 shares, uint256 minAssets, address receiver, address owner)
        internal
        view
        returns (Call memory)
    {
        return _call(
            genericModule1, abi.encodeCall(GenericModule1.erc4626Redeem, (vault, shares, minAssets, receiver, owner))
        );
    }

    /* URD ACTIONS */

    function _urdClaim(
        address distributor,
        address account,
        address reward,
        uint256 amount,
        bytes32[] memory proof,
        bool skipRevert
    ) internal view returns (Call memory) {
        return _call(
            genericModule1,
            abi.encodeCall(GenericModule1.urdClaim, (distributor, account, reward, amount, proof, skipRevert))
        );
    }

    /* MORPHO ACTIONS */

    function _morphoSetAuthorizationWithSig(uint256 privateKey, bool isAuthorized, uint256 nonce, bool skipRevert)
        internal
        view
        returns (Call memory)
    {
        address user = vm.addr(privateKey);

        MorphoBlueAuthorization memory authorization = MorphoBlueAuthorization({
            authorizer: user,
            authorized: address(genericModule1),
            isAuthorized: isAuthorized,
            nonce: nonce,
            deadline: SIGNATURE_DEADLINE
        });

        bytes32 digest = SigUtils.toTypedDataHash(morpho.DOMAIN_SEPARATOR(), authorization);

        MorphoBlueSignature memory signature;
        (signature.v, signature.r, signature.s) = vm.sign(privateKey, digest);

        return _call(
            genericModule1,
            abi.encodeCall(GenericModule1.morphoSetAuthorizationWithSig, (authorization, signature, skipRevert))
        );
    }

    function _morphoSupply(
        MarketParams memory marketParams,
        uint256 assets,
        uint256 shares,
        uint256 slippageAmount,
        address onBehalf,
        bytes memory data
    ) internal view returns (Call memory) {
        return _call(
            genericModule1,
            abi.encodeCall(GenericModule1.morphoSupply, (marketParams, assets, shares, slippageAmount, onBehalf, data))
        );
    }

    function _morphoSupply(
        MarketParams memory marketParams,
        uint256 assets,
        uint256 shares,
        uint256 slippageAmount,
        address onBehalf
    ) internal view returns (Call memory) {
        return _morphoSupply(marketParams, assets, shares, slippageAmount, onBehalf, abi.encode(callbackBundle));
    }

    function _morphoBorrow(
        MarketParams memory marketParams,
        uint256 assets,
        uint256 shares,
        uint256 slippageAmount,
        address receiver
    ) internal view returns (Call memory) {
        return _call(
            genericModule1,
            abi.encodeCall(GenericModule1.morphoBorrow, (marketParams, assets, shares, slippageAmount, receiver))
        );
    }

    function _morphoWithdraw(
        MarketParams memory marketParams,
        uint256 assets,
        uint256 shares,
        uint256 slippageAmount,
        address receiver
    ) internal view returns (Call memory) {
        return _call(
            genericModule1,
            abi.encodeCall(GenericModule1.morphoWithdraw, (marketParams, assets, shares, slippageAmount, receiver))
        );
    }

    function _morphoRepay(
        MarketParams memory marketParams,
        uint256 assets,
        uint256 shares,
        uint256 slippageAmount,
        address onBehalf,
        bytes memory data
    ) internal view returns (Call memory) {
        return _call(
            genericModule1,
            abi.encodeCall(GenericModule1.morphoRepay, (marketParams, assets, shares, slippageAmount, onBehalf, data))
        );
    }

    function _morphoRepay(
        MarketParams memory marketParams,
        uint256 assets,
        uint256 shares,
        uint256 slippageAmount,
        address onBehalf
    ) internal view returns (Call memory) {
        return _morphoRepay(marketParams, assets, shares, slippageAmount, onBehalf, abi.encode(callbackBundle));
    }

    function _morphoSupplyCollateral(
        MarketParams memory marketParams,
        uint256 assets,
        address onBehalf,
        bytes memory data
    ) internal view returns (Call memory) {
        return _call(
            genericModule1,
            abi.encodeCall(GenericModule1.morphoSupplyCollateral, (marketParams, assets, onBehalf, data))
        );
    }

    function _morphoSupplyCollateral(MarketParams memory marketParams, uint256 assets, address onBehalf)
        internal
        view
        returns (Call memory)
    {
        return _morphoSupplyCollateral(marketParams, assets, onBehalf, abi.encode(callbackBundle));
    }

    function _morphoWithdrawCollateral(MarketParams memory marketParams, uint256 assets, address receiver)
        internal
        view
        returns (Call memory)
    {
        return _call(
            genericModule1, abi.encodeCall(GenericModule1.morphoWithdrawCollateral, (marketParams, assets, receiver))
        );
    }

    function _morphoFlashLoan(address token, uint256 amount) internal view returns (Call memory) {
        return _call(
            genericModule1, abi.encodeCall(GenericModule1.morphoFlashLoan, (token, amount, abi.encode(callbackBundle)))
        );
    }

    function _reallocateTo(
        address publicAllocator,
        address vault,
        uint256 value,
        Withdrawal[] memory withdrawals,
        MarketParams memory supplyMarketParams
    ) internal view returns (Call memory) {
        return _call(
            genericModule1,
            abi.encodeCall(
                GenericModule1.reallocateTo, (publicAllocator, vault, value, withdrawals, supplyMarketParams)
            ),
            value
        );
    }

    /* PARASWAP MODULE ACTIONS */

    function _paraswapSell(
        address _augustus,
        bytes memory callData,
        address srcToken,
        address destToken,
        bool sellEntireBalance,
        Offsets memory offsets,
        address receiver
    ) internal pure returns (bytes memory) {
        return abi.encodeCall(
            IParaswapModule.sell, (_augustus, callData, srcToken, destToken, sellEntireBalance, offsets, receiver)
        );
    }

    function _paraswapBuy(
        address _augustus,
        bytes memory callData,
        address srcToken,
        address destToken,
        uint256 newDestAmount,
        Offsets memory offsets,
        address receiver
    ) internal pure returns (bytes memory) {
        return abi.encodeCall(
            IParaswapModule.buy, (_augustus, callData, srcToken, destToken, newDestAmount, offsets, receiver)
        );
    }

    function _sell(
        address srcToken,
        address destToken,
        uint256 srcAmount,
        uint256 minDestAmount,
        bool sellEntireBalance,
        address receiver
    ) internal view returns (Call memory) {
        uint256 fromAmountOffset = 4 + 32 + 32;
        uint256 toAmountOffset = fromAmountOffset + 32;
        return _call(
            paraswapModule,
            _paraswapSell(
                address(augustus),
                abi.encodeCall(augustus.mockSell, (srcToken, destToken, srcAmount, minDestAmount)),
                srcToken,
                destToken,
                sellEntireBalance,
                Offsets({exactAmount: fromAmountOffset, limitAmount: toAmountOffset, quotedAmount: 0}),
                receiver
            )
        );
    }

    function _buy(
        address srcToken,
        address destToken,
        uint256 maxSrcAmount,
        uint256 destAmount,
        uint256 newDestAmount,
        address receiver
    ) internal view returns (Call memory) {
        uint256 fromAmountOffset = 4 + 32 + 32;
        uint256 toAmountOffset = fromAmountOffset + 32;
        return _call(
            paraswapModule,
            _paraswapBuy(
                address(augustus),
                abi.encodeCall(augustus.mockBuy, (srcToken, destToken, maxSrcAmount, destAmount)),
                srcToken,
                destToken,
                newDestAmount,
                Offsets({exactAmount: toAmountOffset, limitAmount: fromAmountOffset, quotedAmount: 0}),
                receiver
            )
        );
    }
}
