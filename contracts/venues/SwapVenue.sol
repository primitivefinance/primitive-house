pragma solidity ^0.7.1;

/**
 * @title A venue used for interacting with uniswap/sushiswap.
 */

// Open Zeppelin
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

// Internal
import {VaultVenue} from "./VaultVenue.sol";
import {SafeMath} from "../libraries/SafeMath.sol";

import "hardhat/console.sol";

contract SwapVenue is VaultVenue {
    using SafeERC20 for IERC20; // Reverts when `transfer` or `transferFrom` erc20 calls don't return proper data
    using SafeMath for uint256; // Reverts on math underflows/overflows

    // the UniswapV2Factory address used by this venue
    address public factory;
    // the UniswapV2Router02 address used by this venue
    address public router;

    // ===== Constructor =====

    constructor(
        address weth_,
        address house_,
        address wToken_,
        address factory_,
        address router_
    ) VaultVenue(weth_, house_, wToken_) {
      factory = factory_;
      router = router_;
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
