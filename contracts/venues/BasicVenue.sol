pragma solidity ^0.7.1;

/**
 * @title Utilized for ongoing development.
 */

// Open Zeppelin
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

// Primitive
import {PrimitiveERC20} from "../PrimitiveERC20.sol";

// Internal
import {Venue} from "./Venue.sol";
import {IHouse} from "../interfaces/IHouse.sol";
import {IWETH} from "../interfaces/IWETH.sol";
import {SafeMath} from "../libraries/SafeMath.sol";

import "hardhat/console.sol";

contract BasicVenue is Venue, PrimitiveERC20 {
    using SafeERC20 for IERC20; // Reverts when `transfer` or `transferFrom` erc20 calls don't return proper data
    using SafeMath for uint256; // Reverts on math underflows/overflows

    event Initialized(address indexed from); // Emmitted on deployment

    // ===== Constructor =====

    constructor(
        address weth_,
        address house_,
        address wToken_
    ) public Venue(weth_, house_, wToken_) {
        initialize("Primitive Basic Vault Token", "pBasic");
        emit Initialized(msg.sender);
    }

    // ===== Mutable =====

    mapping(address => mapping(address => uint256)) public balanceOfUser;
    event Deposit(address indexed token, uint256 amount, address receiver);
    event Withdraw(address indexed token, uint256 amount, address receiver);

    /**
     * @notice A basic function to deposit an option into this contract's internal balance.
     */
    function deposit(
        bytes32 oid,
        uint256 amount,
        address receiver
    ) public returns (bool) {
        // Receivers are this address
        address[] memory receivers = new address[](2);
        receivers[0] = address(this);
        receivers[1] = address(this);

        console.log("minting options");
        // Call the house to mint options
        house.mintOptions(oid, amount, receivers);
        // Get option addresses
        (address long, address short) = house.getOptionTokens(oid);
        console.log("updating balances");
        // Update long balance
        _depositToken(receiver, long, amount);
        // Update short balance
        _depositToken(receiver, long, amount);
        return true;
    }

    function withdraw(
        bytes32 oid,
        uint256 amount,
        address[] memory receivers
    ) public returns (bool) {
        // Get option addresses
        (address long, address short) = house.getOptionTokens(oid);
        console.log("updating balances");
        address primary = receivers[0];
        address secondary = receivers[1];
        // Update long balance
        _withdrawToken(primary, long, amount);
        // Update short balance
        _withdrawToken(secondary, long, amount);
        // pushing tokens
        IERC20(long).safeTransfer(primary, amount);
        IERC20(short).safeTransfer(secondary, amount);
        return true;
    }

    function _withdrawToken(
        address account,
        address token,
        uint256 amount
    ) internal {
        // Update short balance
        _updateBalance(
            account,
            token,
            balanceOfUser[account][token].sub(amount)
        );
        // Emit a deposit event for each token
        emit Withdraw(token, amount, account);
        console.log("withdrawn");
    }

    function depositToken(
        address token,
        uint256 amount,
        address receiver
    ) public returns (bool) {
        // Receivers are this address
        address[] memory receivers = new address[](2);
        receivers[0] = address(this);
        receivers[1] = address(this);
        // Update long balance
        _depositToken(receiver, token, amount);
        _requestTokens(token, amount);
        return true;
    }

    /**
     * @notice A basic function to deposit an option into a wrap token, and return it to the house.
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
        // Call the house to mint options, pulls base tokens to the house from the executing caller
        house.mintOptions(oid, amount, receivers);
        // Get option addresses
        (address long, address short) = house.getOptionTokens(oid);
        // Send option tokens to a wrapped token, which is then sent back to the house.
        _wrapOptionForHouse(oid, amount);
        return true;
    }

    /**
     * @notice  Takes a wrapped option from the house, and splits it to amounts which are sent to receivers.
     */
    function splitOptionsAndDeposit(
        bytes32 oid,
        uint256 amount,
        address[] memory receivers
    ) public {
        console.log("unwrapping options");
        // Unwrap the collateral from the House
        _optionUnwrapFromHouse(oid, amount);
        console.log("depositing to this contract");
        // Deposit the option ERC20s to this contract
        (address long, address short) = house.getOptionTokens(oid);
        _depositToken(receivers[0], long, amount);
        _depositToken(receivers[1], short, amount);
    }

    /**
     * @notice  Exercises the `oid` option using the balance of the long stored in this contract.
     */
    function exerciseFromBalance(
        bytes32 oid,
        uint256 amount,
        address receiver
    ) public {
        (address long, ) = house.getOptionTokens(oid);
        uint256 balance = balanceOfUser[house.getExecutingCaller()][long];
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
        (address long, ) = house.getOptionTokens(oid);
        uint256 balance = balanceOfUser[house.getExecutingCaller()][long];
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
        (, address short) = house.getOptionTokens(oid);
        uint256 balance = balanceOfUser[house.getExecutingCaller()][short];
        console.log("checking balance in venue", balance, amount);
        require(balance >= amount, "Venue: ABOVE_MAX");
        // exercise options using the House
        console.log("venue._exerciseOptions");
        _redeemOptions(oid, amount, receiver, true);
    }

    function redeemFromWrappedBalance(
        bytes32 oid,
        uint256 amount,
        address receiver
    ) public {
        // Receivers are this address
        address[] memory receivers = new address[](2);
        receivers[0] = address(this);
        receivers[1] = address(this);
        splitOptionsAndDeposit(oid, amount, receivers);

        (address long, ) = house.getOptionTokens(oid);
        uint256 balance = balanceOfUser[house.getExecutingCaller()][long];
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

        (address long, ) = house.getOptionTokens(oid);
        uint256 balance = balanceOfUser[house.getExecutingCaller()][long];
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
        (address long, ) = house.getOptionTokens(oid);
        uint256 balance = balanceOfUser[house.getExecutingCaller()][long];
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
        (address long, ) = house.getOptionTokens(oid);
        uint256 balance = balanceOfUser[house.getExecutingCaller()][long];
        console.log("checking balance in venue", balance, amount);
        require(balance >= amount, "Venue: ABOVE_MAX");
        // exercise options using the House
        console.log("venue._closeOptions");
        _closeOptions(oid, amount, receiver, false);
    }

    function _depositToken(
        address account,
        address token,
        uint256 amount
    ) internal {
        // Update short balance
        _updateBalance(
            account,
            token,
            balanceOfUser[account][token].add(amount)
        );
        // Emit a deposit event for each token
        emit Deposit(token, amount, account);
        console.log("deposited");
    }

    function _updateBalance(
        address account,
        address token,
        uint256 amount
    ) internal {
        balanceOfUser[account][token] = amount;
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
