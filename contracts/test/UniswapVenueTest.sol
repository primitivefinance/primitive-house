// SPDX-License-Identifier: MIT
pragma solidity >=0.6.2;

/**
 * @title   A Test Contract Version of the UniswapVenue for Custom Uniswap Addresses
 * @notice  UniswapVenue
 * @author  Primitive
 */

import {
    UniswapVenue,
    IUniswapV2Factory,
    IUniswapV2Router02
} from "../UniswapVenue.sol";

contract UniswapVenueTest is UniswapVenue {
    constructor(
        address weth_,
        address house_,
        address capitol_,
        address router_,
        address factory_
    ) public UniswapVenue(weth_, house_, capitol_) {
        factory = IUniswapV2Factory(factory_);
        router = IUniswapV2Router02(router_);
    }
}
