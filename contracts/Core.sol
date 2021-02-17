pragma solidity ^0.7.1;
pragma experimental ABIEncoderV2;

/**
 * @title   The low-level contract for core option logic.
 *          Holds option parameter data structures, and a token cloner.
 * @notice  Warning: This contract should only be called by higher-level contracts.
 * @author  Primitive
 */

import {Registry} from "./Registry.sol";
import {IPrimitiveERC20, IERC20} from "./interfaces/IPrimitiveERC20.sol";
import {IWToken} from "./interfaces/IWToken.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";

import {IManager} from "./interfaces/IManager.sol";
import {ICore} from "./interfaces/ICore.sol";

import "hardhat/console.sol";

contract Core is ICore, Registry {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    /**
     * @dev The higher-level managing contract for this option core.
     */
    IManager internal immutable _manager;

    /**
     * @notice Only allow `_manager` to call functions with this modifier.
     */
    modifier onlyManager() {
        require(address(_manager) == msg.sender, "Core: NOT_MANAGER");
        _;
    }

    constructor(IManager manager_) {
        _manager = manager_;
    }

    function getManager() public view returns (address) {
        return address(_manager);
    }

    // ===== Option Core =====

    /**
     * @dev Mint the `oid` long + short option tokens to `receivers`.
     */
    function dangerousMint(
        bytes32 oid,
        uint256 amount,
        address[] memory receivers
    ) public override onlyManager returns (uint256) {
        console.log("minting internally");
        _internalMint(oid, amount, receivers);
        return amount;
    }

    function _internalMint(
        bytes32 oid,
        uint256 amount,
        address[] memory receivers
    ) internal {
        TokenData memory data = _tokenData[oid];
        IPrimitiveERC20(data.longToken).mint(receivers[0], amount);
        IPrimitiveERC20(data.shortToken).mint(receivers[1], amount);
        console.log("minted tokens");
    }

    /**
     * @notice  Burns `amount` of long option tokens and returns the amount quote tokens required for payment.
     */
    function dangerousExercise(
        bytes32 oid,
        address sender,
        uint256 amount
    ) public override onlyManager returns (uint256, uint256) {
        (, , uint256 strikePrice, , ) = getParameters(oid);

        // burn the long options
        TokenData memory data = _tokenData[oid];
        IPrimitiveERC20(data.longToken).burn(sender, amount);

        // return necessary amounts
        uint256 lessBase = amount;
        uint256 plusQuote = amount.mul(strikePrice).div(1 ether);
        return (lessBase, plusQuote);
    }

    function dangerousRedeem(
        bytes32 oid,
        address sender,
        uint256 amount,
        uint256 minOutputQuote,
        uint256 quoteBalance
    ) public override onlyManager returns (uint256) {
        // burn the long options
        TokenData memory data = _tokenData[oid];
        address short = data.shortToken;
        uint256 shortSupply = IERC20(short).totalSupply();

        if (minOutputQuote > 0) {
            console.log("checking redeem amt");
            console.log(minOutputQuote, shortSupply, amount, quoteBalance);
            require(
                minOutputQuote.mul(shortSupply) == amount.mul(quoteBalance),
                "Core: QUOTE_BALANCE"
            );
            IPrimitiveERC20(short).burn(sender, amount);
        }

        // return necessary inputShort amounts
        console.log(amount, shortSupply, quoteBalance);
        uint256 lessQuote = amount.mul(quoteBalance).div(shortSupply);
        return lessQuote;
    }

    function dangerousClose(
        bytes32 oid,
        address sender,
        uint256 amount
    ) public override onlyManager returns (uint256) {
        // burn the long options
        TokenData memory data = _tokenData[oid];
        console.log("burning tokens");
        IPrimitiveERC20(data.longToken).burn(
            IManager(msg.sender).getExecutingVenue(),
            amount
        ); // fix from address
        // burn the short options
        IPrimitiveERC20(data.shortToken).burn(
            IManager(msg.sender).getExecutingVenue(),
            amount
        ); // fix from address
        // return necessary amounts
        console.log("burnt closed tokens");
        return amount;
    }

    // ===== View =====

    function getOptionBalances(bytes32 oid, address account)
        public
        view
        override
        returns (uint256[] memory)
    {
        TokenData memory data = _tokenData[oid];
        uint256[] memory balances = new uint256[](2);
        balances[0] = IERC20(data.longToken).balanceOf(account);
        balances[1] = IERC20(data.shortToken).balanceOf(account);
        return balances;
    }
}
