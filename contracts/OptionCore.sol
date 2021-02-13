pragma solidity ^0.7.1;
pragma experimental ABIEncoderV2;

/**
 * @title   The low-level contract for core option logic.
 *          Holds option parameter data structures, and a token cloner.
 * @notice  Warning: This contract should only be called by higher-level contracts.
 * @author  Primitive
 */

import {OptionData} from "./OptionData.sol";
import {IPrimitiveERC20, IERC20} from "./interfaces/IPrimitiveERC20.sol";
import {IWToken} from "./interfaces/IWToken.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";

import {IManager} from "./interfaces/IManager.sol";
import {IOptionCore} from "./interfaces/IOptionCore.sol";

contract OptionCore is IOptionCore, OptionData {
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
     * @dev Mint the `oid` long + short option tokens to `receivers` using the mintingInvariant function.
     */
    function dangerousMint(
        bytes memory oid,
        uint256 amount,
        address[] memory receivers
    ) public override onlyManager returns (uint256) {
        _internalMint(oid, amount, receivers);
        return amount;
    }

    function _internalMint(
        bytes memory oid,
        uint256 amount,
        address[] memory receivers
    ) internal {
        TokenData memory data = _tokenData[oid];
        IPrimitiveERC20(data.longToken).mint(receivers[0], amount);
        IPrimitiveERC20(data.shortToken).mint(receivers[1], amount);
    }

    /**
     * @notice Long option tokens are burned on exercise.
     */
    function dangerousExercise(
        bytes memory oid,
        uint256 amount,
        uint256[] memory claimAmounts,
        address burnedFrom
    ) public override onlyManager returns (uint256[] memory) {
        uint256 baseClaim = claimAmounts[0];
        uint256 quoteClaim = claimAmounts[1];
        _internalLongBurn(oid, amount, burnedFrom);
        Parameters memory params = _parameters[oid];
        // Recycle claimAmounts array
        claimAmounts[0] = baseClaim.sub(amount);
        claimAmounts[1] = quoteClaim.add(
            amount.mul(params.strikePrice).div(1 ether)
        );
        return claimAmounts;
    }

    /**
     * @notice Short option tokens are burned.
     */
    function dangerousSettle(
        bytes memory oid,
        uint256 amount,
        uint256[] memory claimAmounts,
        address burnFrom
    ) public override onlyManager returns (uint256[] memory) {
        _internalShortBurn(oid, amount, burnFrom);
        // Subtract proportional amounts of each amount.
        TokenData memory data = _tokenData[oid];
        uint256 shortSupply = IERC20(data.shortToken).totalSupply();
        uint256 baseClaim = claimAmounts[0];
        uint256 quoteClaim = claimAmounts[1];
        claimAmounts[0] = baseClaim.mul(shortSupply).div(amount);
        claimAmounts[1] = quoteClaim.mul(shortSupply).div(amount);
        return claimAmounts;
    }

    /**
     * @notice Long and short option tokens are burned.
     */
    function dangerousClose(
        bytes memory oid,
        uint256[] memory amounts,
        uint256[] memory claimAmounts,
        address[] memory accounts
    ) public override onlyManager returns (uint256[] memory) {
        _internalBurn(oid, amounts, accounts);
        // Subtract proportional amounts of each amount.
        TokenData memory data = _tokenData[oid];
        uint256 shortSupply = IERC20(data.shortToken).totalSupply();
        uint256 longSupply = IERC20(data.longToken).totalSupply();
        uint256 baseClaim = claimAmounts[0];
        uint256 quoteClaim = claimAmounts[1];
        claimAmounts[0] = baseClaim.mul(longSupply).div(amounts[0]);
        claimAmounts[1] = quoteClaim.mul(shortSupply).div(amounts[1]);
        return claimAmounts;
    }

    function _internalBurn(
        bytes memory oid,
        uint256[] memory amounts,
        address[] memory accounts
    ) internal {
        TokenData memory data = _tokenData[oid];
        IPrimitiveERC20(data.longToken).burn(accounts[0], amounts[0]);
        IPrimitiveERC20(data.shortToken).burn(accounts[1], amounts[1]);
    }

    function _internalLongBurn(
        bytes memory oid,
        uint256 amount,
        address account
    ) internal returns (bool) {
        TokenData memory data = _tokenData[oid];
        return IPrimitiveERC20(data.longToken).burn(account, amount);
    }

    function _internalShortBurn(
        bytes memory oid,
        uint256 amount,
        address account
    ) internal returns (bool) {
        TokenData memory data = _tokenData[oid];
        return IPrimitiveERC20(data.shortToken).burn(account, amount);
    }

    // ===== View =====

    function getOptionBalances(bytes memory oid, address account)
        public
        view
        returns (uint256[] memory)
    {
        TokenData memory data = _tokenData[oid];
        uint256[] memory balances = new uint256[](2);
        balances[0] = IERC20(data.longToken).balanceOf(account);
        balances[1] = IERC20(data.shortToken).balanceOf(account);
        return balances;
    }
}
