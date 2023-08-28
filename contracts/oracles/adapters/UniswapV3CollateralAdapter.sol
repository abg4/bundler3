// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IUniswapV3Pool} from "@uniswap/v3-core/interfaces/IUniswapV3Pool.sol";

import {ErrorsLib} from "../libraries/ErrorsLib.sol";
import {UniswapV3PoolLib} from "./libraries/UniswapV3PoolLib.sol";

import {BaseOracle} from "../BaseOracle.sol";

abstract contract UniswapV3CollateralAdapter is BaseOracle {
    using UniswapV3PoolLib for IUniswapV3Pool;

    IUniswapV3Pool private immutable _UNI_V3_COLLATERAL_POOL;

    uint32 public immutable COLLATERAL_WINDOW;
    bool public immutable COLLATERAL_PRICE_INVERSED;

    constructor(address pool, uint32 window, address quoteToken) {
        require(pool != address(0), ErrorsLib.ZERO_ADDRESS);
        require(window > 0, ErrorsLib.ZERO_INPUT);

        _UNI_V3_COLLATERAL_POOL = IUniswapV3Pool(pool);

        address token0 = _UNI_V3_COLLATERAL_POOL.token0();
        address token1 = _UNI_V3_COLLATERAL_POOL.token1();
        require(quoteToken == token0 || quoteToken == token1, ErrorsLib.INVALID_QUOTE_TOKEN);

        COLLATERAL_WINDOW = window;
        COLLATERAL_PRICE_INVERSED = quoteToken == token0;

        COLLATERAL_SCALE = 1 << 128;
    }

    function COLLATERAL_FEED() external view returns (address) {
        return address(_UNI_V3_COLLATERAL_POOL);
    }

    function collateralPrice() public view virtual override returns (uint256) {
        return _UNI_V3_COLLATERAL_POOL.priceX128(COLLATERAL_WINDOW, COLLATERAL_PRICE_INVERSED);
    }
}
