// SPDX-License-Identifier: MIT
pragma solidity >=0.6.2;

/**
 * @title   A Test Contract Version of the SushiSwapVenue for Custom Uniswap Addresses
 * @notice  SushiSwapVenue
 * @author  Primitive
 */

import {
    SushiSwapVenue,
    IUniswapV2Factory,
    IUniswapV2Router02
} from "../venues/SushiSwapVenue.sol";

contract SushiSwapVenueTest is SushiSwapVenue {
    constructor(
        address weth_,
        address house_,
        address capitol_,
        address router_,
        address factory_
    ) public SushiSwapVenue(weth_, house_, capitol_) {
        factory = IUniswapV2Factory(factory_);
        router = IUniswapV2Router02(router_);
    }
}
