// SPDX-License-Identifier: MIT
pragma solidity ^0.7.1;

/**
 * @title   SwapVenue -> used by House to interact with Uniswap or Sushiswap
 * @author  Primitive
 * @notice  This implementation is not complete, DO NOT DEPLOY.
 */

// Open Zeppelin
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

// Uniswap
import {
    IUniswapV2Router02
} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

// Internal
import {ISwapVenue} from "../interfaces/ISwapVenue.sol";
import {Venue} from "./Venue.sol";
import {SafeMath} from "../libraries/SafeMath.sol";

// dev
import "hardhat/console.sol";

contract SwapVenue is Venue, ISwapVenue {
    using SafeERC20 for IERC20; // Reverts when `transfer` or `transferFrom` erc20 calls don't return proper data
    using SafeMath for uint256; // Reverts on math underflows/overflows

    // the UniswapV2Router02 address used by this venue
    IUniswapV2Router02 private _router;

    // ===== Constructor =====

    constructor(
        address weth_,
        address house_,
        address wToken_,
        address router_
    ) Venue(weth_, house_, wToken_) {
      _router = IUniswapV2Router02(router_);
    }

    event AddedLiquidity(
      address tokenA,
      address tokenB,
      uint256 amountA,
      uint256 amountB,
      uint256 liquidity
    );

    // ===== Mutable =====
    /**
     * @notice  Adds short/underlying liquidity to the pool.
     * @param   oid The target option.
     * @param   amount How much option token to mint and add as liquidity.
     * @param   deadline The deadline for the swap transaction.
     */
    function addShortLiquidityWithUnderlying(
      bytes32 oid,
      uint256 amount,
      uint256 deadline
    ) external override {
      // get parameters from option
      (address underlying, , , ,) = _house.getParameters(oid);

      address[] memory receivers = new address[](2);
      // house will keep long tokens
      receivers[0] = address(_house);
      // this contract gets short tokens
      receivers[1] = address(this);

      console.log("minting options");
      // mint options using house, sending short tokens to this contract and keeping exercise tokens in the house.
      _mintOptions(oid, amount, receivers, false);
      // get short token address
      (, address short) = _house.getOptionTokens(oid);

      // pull additional underlying tokens from caller TODO what is correct amount to pull
      console.log("pulling tokens from user");
      _house.takeTokensFromUser(underlying, amount);

      // make sure both underlying and short are approved to be pulled by uniswap router
      checkApproved(underlying, address(_router));
      checkApproved(short, address(_router));
      // add liquidity to the pool with underlying/short tokens using all the short tokens up
      console.log("add liquidity to pool");
      // store LP tokens in house
      (uint256 amountA, uint256 amountB, uint256 liquidity) = _router.addLiquidity(
        short,
        underlying,
        amount,
        amount,
        0,
        0,
        address(_house),
        deadline
      );
      emit AddedLiquidity(short, underlying, amountA, amountB, liquidity);
      // return excess underlying tokens to caller
      IERC20(underlying).safeTransfer(_house.getExecutingCaller(), IERC20(underlying).balanceOf(address(this)));
      // emit event?
    }

    /**
     * @notice  Adds long/underlying liquidity to the pool.
     * @param   oid The target option.
     * @param   amount How much option token to mint and add as liquidity.
     * @param   deadline The deadline for the swap transaction.
     */
    function addLongLiquidityWithUnderlying(
      bytes32 oid,
      uint256 amount,
      uint256 deadline
    ) external override {
      // get parameters from option
      (address underlying, , , ,) = _house.getParameters(oid);

      address[] memory receivers = new address[](2);
      // this contract gets long tokens
      receivers[0] = address(this);
      // the house gets short tokens
      receivers[1] = address(_house);

      console.log("minting options");
      // mint options using house, sending long tokens to this contract and keeping exercise tokens in the house.
      _mintOptions(oid, amount, receivers, false);
      // get option token address
      (address long, ) = _house.getOptionTokens(oid);

      // pull additional underlying tokens from caller TODO what is correct amount to pull
      console.log("pulling tokens from user");
      _house.takeTokensFromUser(underlying, amount);

      // make sure both underlying and long are approved to be pulled by uniswap router
      checkApproved(underlying, address(_router));
      checkApproved(long, address(_router));
      // add liquidity to the pool with underlying/long tokens using all the long tokens up
      console.log("add liquidity to pool");
      // store LP tokens in house
      (uint256 amountA, uint256 amountB, uint256 liquidity) = _router.addLiquidity(
        long,
        underlying,
        amount,
        amount,
        0,
        0,
        address(_house),
        deadline
      );
      emit AddedLiquidity(long, underlying, amountA, amountB, liquidity);
      // return excess underlying tokens to caller
      IERC20(underlying).safeTransfer(_house.getExecutingCaller(), IERC20(underlying).balanceOf(address(this)));
      // emit event?
    }

    // ===== Test =====

    uint256 private _test;

    function getTest() public view returns (uint256) {
        return _test;
    }

    event SetTest(uint256 value);

    function setTest(uint256 value) public {
        _test = value;

        emit SetTest(value);
    }

    // ===== View =====
}
