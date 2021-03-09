pragma solidity ^0.7.1;

/**
 * @title Utilized for ongoing development.
 */

// Open Zeppelin
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

// Uniswap
import {
    IUniswapV2Pair
} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import {
    IUniswapV2Router02
} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import {
    IUniswapV2Factory
} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";

// Internal
import {VaultVenue} from "./VaultVenue.sol";
import {SafeMath} from "../libraries/SafeMath.sol";

import "hardhat/console.sol";

contract SushiVenue is VaultVenue {
    using SafeERC20 for IERC20; // Reverts when `transfer` or `transferFrom` erc20 calls don't return proper data
    using SafeMath for uint256; // Reverts on math underflows/overflows

    IUniswapV2Factory public factory =
        IUniswapV2Factory(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f); // The Uniswap V2 factory contract to get pair addresses from
    IUniswapV2Router02 public router =
        IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D); // The Uniswap contract used to interact with the protocol

    // ===== Constructor =====

    constructor(
        address weth_,
        address house_,
        address wToken_,
        address factory_,
        address router_
    ) VaultVenue(weth_, house_, wToken_) {
      factory = IUniswapV2Factory(factory_);
      router = IUniswapV2Router02(router_);
    }

    // ===== Mutable =====

    /**
     * @notice A basic function to deposit an option into a wrap token, and return it to the _house.
     */
    function mintOptionsThenWrap(
        bytes32 oid,
        uint256 amount,
        address receiver
    ) public returns (bool) {
        // Receivers are this address
        address[] memory receivers = new address[](2);
        receivers[0] = address(this);
        receivers[1] = address(this);

        console.log("minting options");
        // Call the _house to mint options, pulls base tokens to the _house from the executing caller
        _mintOptions(oid, amount, receivers, false);
        // Get option addresses
        (address long, address short) = _house.getOptionTokens(oid);
        // Send option tokens to a wrapped token, which is then sent back to the _house.
        _wrapOptionForHouse(oid, amount);
        return true;
    }
// let a venue borrow options. TEST FUNCTION ONLY DO NOT DEPLOY
// todo make specific VenueTest.sol with test utility fns
    function borrowOptionTest(
      bytes32 oid,
      uint256 amount
    ) public returns (bool) {
      // Receivers are this address
      address[] memory receivers = new address[](2);
      receivers[0] = address(this);
      receivers[1] = address(this);

      _house.borrowOptions(oid, amount, receivers);
      return true;
    }

    /**
     * @notice  Exercises the `oid` option using the balance of the long stored in this contract.
     */
    function exerciseFromBalance(
        bytes32 oid,
        uint256 amount,
        address receiver
    ) public {
        (address long, ) = _house.getOptionTokens(oid);
        uint256 balance = balanceOfUser[_house.getExecutingCaller()][long];
        console.log("checking balance in venue", balance, amount);
        require(balance >= amount, "Venue: ABOVE_MAX");
        // exercise options using the House
        console.log("venue._exerciseOptions");
        _exerciseOptions(oid, amount, receiver, true);
    }

    function exerciseFromWrappedBalance(
        bytes32 oid,
        uint256 amount,
        address receiver
    ) public {
        // Receivers are this address
        address[] memory receivers = new address[](2);
        receivers[0] = address(this);
        receivers[1] = address(this);
        splitOptionsAndDeposit(oid, amount, receivers);
        (address long, ) = _house.getOptionTokens(oid);
        uint256 balance = balanceOfUser[_house.getExecutingCaller()][long];
        console.log("checking balance in venue", balance, amount);
        require(balance >= amount, "Venue: ABOVE_MAX");
        // exercise options using the House
        console.log("venue._exerciseOptions");
        _exerciseOptions(oid, amount, receiver, true);
    }

    function redeemFromBalance(
        bytes32 oid,
        uint256 amount,
        address receiver
    ) public {
        (, address short) = _house.getOptionTokens(oid);
        uint256 balance = balanceOfUser[_house.getExecutingCaller()][short];
        console.log("checking balance in venue", balance, amount);
        require(balance >= amount, "Venue: ABOVE_MAX");
        // exercise options using the House
        console.log("venue._exerciseOptions");
        _redeemOptions(oid, amount, receiver, true);
    }

    function closeFromWrappedBalance(
        bytes32 oid,
        uint256 amount,
        address receiver
    ) public {
        // Receivers are this address
        address[] memory receivers = new address[](2);
        receivers[0] = address(this);
        receivers[1] = address(this);
        splitOptionsAndDeposit(oid, amount, receivers);

        (address long, ) = _house.getOptionTokens(oid);
        uint256 balance = balanceOfUser[_house.getExecutingCaller()][long];
        console.log("checking balance in venue", balance, amount);
        require(balance >= amount, "Venue: ABOVE_MAX");
        // exercise options using the House
        console.log("venue._exerciseOptions");
        _closeOptions(oid, amount, receiver, true);
    }

    function closeFromBalance(
        bytes32 oid,
        uint256 amount,
        address receiver
    ) public {
        (address long, ) = _house.getOptionTokens(oid);
        uint256 balance = balanceOfUser[_house.getExecutingCaller()][long];
        console.log("checking balance in venue", balance, amount);
        require(balance >= amount, "Venue: ABOVE_MAX");
        // exercise options using the House
        console.log("venue._closeOptions");
        _closeOptions(oid, amount, receiver, true);
    }

    function close(
        bytes32 oid,
        uint256 amount,
        address receiver
    ) public {
        (address long, ) = _house.getOptionTokens(oid);
        uint256 balance = balanceOfUser[_house.getExecutingCaller()][long];
        console.log("checking balance in venue", balance, amount);
        require(balance >= amount, "Venue: ABOVE_MAX");
        // exercise options using the House
        console.log("venue._closeOptions");
        _closeOptions(oid, amount, receiver, false);
    }

    // ===== Liquidity ======
    // mint mintAmount of option oid
    // deposit at least addAmountMin and at most addAmountMax of underlying plus
    // mintAmount redeem tokens in the liquidity pool, send LP tokens to House
    // send spare underlying back to original caller
    // deadline the timestamp to expire a pending transaction
    function addRedeemLiquidityWithUnderlying(
        bytes32 oid,
        uint256 mintAmount,
        uint256 addAmountMax,
        uint256 addAmountMin,
        uint256 deadline
    ) external {
      // house will get long tokens, while short tokens are minted to this contract before being added to liquidity pool
      address[] memory receivers = new address[](2);
      receivers[0] = address(_house);
      receivers[1] = address(this);

      console.log("minting options");
      // Call the _house to mint options, pulls base tokens to the _house from the executing caller
      _mintOptions(oid, mintAmount, receivers, false);
      (, address redeem) = _house.getOptionTokens(oid);
      (, address underlying, , ,) = _house.getParameters(oid);
      // call the house to pull addAmountMax of underlying token into this contract
      _house.takeTokensFromUser(underlying, addAmountMax);

      // add liquidity to uniswap using UniswapV2Router02
      // will revert if this contract has approved the target pool yet for underlying
      // add exactly mintAmount of redeem tokens,
      // and between addAmountMin and addAmountMax of underlying
      // to pool by deadline
      // mint LP tokens to the house
      router.addLiquidity(
                redeem,
                underlying,
                mintAmount,
                addAmountMax,
                addAmountMin,
                mintAmount,
                address(_house),
                deadline
            );

      // emit event?

    }

    // ===== Flash Loans =====



    function _flashSwap(
        IUniswapV2Pair pair,
        address token,
        uint256 amount,
        bytes memory params
    ) internal returns (bool) {
        // Receives `amount` of `token` to this contract address.
        uint256 amount0Out = pair.token0() == token ? amount : 0;
        uint256 amount1Out = pair.token0() == token ? 0 : amount;
        // Execute the callback function in params.
        pair.swap(amount0Out, amount1Out, address(this), params);
        return true;
    }

    /**
      * @dev     The callback function triggered in a UniswapV2Pair.swap() call when the `data` parameter has data.
      * @param   sender The original msg.sender of the UniswapV2Pair.swap() call.
      * @param   amount0 The quantity of token0 received to the `to` address in the swap() call.
      * @param   amount1 The quantity of token1 received to the `to` address in the swap() call.
      * @param   data The payload passed in the `data` parameter of the swap() call.
      */
      function uniswapV2Call(
        address sender,
        uint256 amount0,
        uint256 amount1,
        bytes calldata data
      ) external {
            require(
              msg.sender ==
              factory.getPair(
                  IUniswapV2Pair(msg.sender).token0(),
                  IUniswapV2Pair(msg.sender).token1()
              )
            ); // ensure that msg.sender is actually a V2 pair
            require(sender == address(this), "NOT_SENDER"); // ensure called by this contract
            (bool success, bytes memory returnData) = address(this).call(data);
            require(
                success &&
                (returnData.length == 0 || abi.decode(returnData, (bool))),
                "CALLBACK"
            );
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
