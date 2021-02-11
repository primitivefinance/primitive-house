pragma solidity ^0.7.1;
pragma experimental ABIEncoderV2;

/**
 * @title   The low-level contract for core option logic.
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
     * @notice Event emitted after a `dangerousMint` has succeeded.
     */
    event OptionsMinted(
        address indexed from,
        uint256 amount,
        address indexed longReceiver,
        address indexed shortReceiver
    );

    /**
     * @notice Event emitted after a `dangerousBurn` has succeeded.
     */
    event OptionsBurned(
        address indexed from,
        uint256 longAmount,
        uint256 shortAmount,
        address indexed longReceiver,
        address indexed shortReceiver
    );

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
     * @dev Mint the `oid` option tokens to `receivers` using the mintingInvariant function.
     */
    function dangerousMint(
        bytes memory oid,
        uint256 requestAmt,
        address[] memory receivers
    ) public override returns (bool, uint256) {
        // mint invariant -> replace with a fn from option manager
        (bool success, uint256 actualAmt) =
            _manager.mintingInvariant(oid, requestAmt);
        require(success && actualAmt >= requestAmt, "Core: MINT_FAIL");
        _internalMint(oid, actualAmt, receivers);
        emit OptionsMinted(msg.sender, actualAmt, receivers[0], receivers[1]);
        return (success, actualAmt);
    }

    function _internalMint(
        bytes memory oid,
        uint256 amount,
        address[] memory receivers
    ) internal returns (bool) {
        TokenData memory data = _tokenData[oid];
        address longReceiver = receivers[0];
        address shortReceiver = receivers[1];
        bool success =
            IPrimitiveERC20(data.longToken).mint(longReceiver, amount);
        bool shortSuccess =
            IPrimitiveERC20(data.shortToken).mint(shortReceiver, amount);
        return success && shortSuccess;
    }

    /**
     * @dev Burn the `oid` option tokens using the burningInvariant function.
     */
    /* function dangerousBurn(
        bytes memory oid,
        uint256[] memory amounts,
        address[] memory accounts
    ) public override returns (bool) {
        uint256 amount0 = amounts[0];
        uint256 amount1 = amounts[1];
        require(
            amount0 > uint256(0) && amount1 > uint256(0),
            "Core: ZERO_BURN"
        );

        bool invariant;
        if (amount0 == uint256(0)) {
            // if no long tokens are being burned, its a settlement
            invariant = _manager.settlementInvariant(oid, amounts);
            // if settlement invariant is not cleared, revert.
            require(invariant, "Core: SETTLE_FAIL");
        } else if (amount1 == uint256(0)) {
            // if no short tokens are being burned, its an exercise.
            invariant = _manager.exerciseInvariant(oid, amounts);
            // if exercise invariant is not cleared, revert.
            require(invariant, "Core: EXERCISE_FAIL");
        } else {
            // if short and long tokens are burned, its a close.
            invariant = _manager.closeInvariant(oid, amounts);
            // if close invariant is not cleared, revert.
            require(invariant, "Core: CLOSE_FAIL");
        }

        _internalBurn(oid, amounts, accounts);
        emit OptionsBurned(
            msg.sender,
            amount0,
            amount1,
            accounts[0],
            accounts[1]
        );
        return invariant;
    } */

    function dangerousBurn(
        bytes memory oid,
        uint256[] memory amounts,
        address[] memory accounts
    ) public override returns (bool) {
        uint256 amount0 = amounts[0];
        uint256 amount1 = amounts[1];
        require(
            amount0 > uint256(0) && amount1 > uint256(0),
            "Core: ZERO_BURN"
        );

        // if short and long tokens are burned, its a close.
        bool invariant = _manager.closeInvariant(oid, amounts);
        // if close invariant is not cleared, revert.
        require(invariant, "Core: CLOSE_FAIL");

        _internalBurn(oid, amounts, accounts);
        emit OptionsBurned(
            msg.sender,
            amount0,
            amount1,
            accounts[0],
            accounts[1]
        );
        return invariant;
    }

    function dangerousLongBurn(
        bytes memory oid,
        uint256 amount,
        address account
    ) public override returns (bool) {
        require(amount > uint256(0), "Core: ZERO_BURN");
        // if no short tokens are being burned, its an exercise.
        bool invariant = _manager.exerciseInvariant(oid, amount);
        // if exercise invariant is not cleared, revert.
        require(invariant, "Core: EXERCISE_FAIL");
        _internalLongBurn(oid, amount, account);
        emit OptionsBurned(
            msg.sender,
            amount,
            uint256(0),
            account,
            address(0x0)
        );
        return invariant;
    }

    function dangerousShortBurn(
        bytes memory oid,
        uint256 amount,
        address account
    ) public override returns (bool) {
        require(amount > uint256(0), "Core: ZERO_BURN");

        // if no long tokens are being burned, its a settlement
        bool invariant = _manager.settlementInvariant(oid, amount);
        // if settlement invariant is not cleared, revert.
        require(invariant, "Core: SETTLE_FAIL");

        _internalShortBurn(oid, amount, account);
        emit OptionsBurned(
            msg.sender,
            uint256(0),
            amount,
            address(0x0),
            account
        );

        return invariant;
    }

    function _internalBurn(
        bytes memory oid,
        uint256[] memory amounts,
        address[] memory accounts
    ) internal returns (bool) {
        TokenData memory data = _tokenData[oid];
        address longHolder = accounts[0];
        address shortHolder = accounts[1];
        uint256 longAmount = amounts[0];
        uint256 shortAmount = amounts[1];
        bool success =
            IPrimitiveERC20(data.longToken).burn(longHolder, longAmount);
        bool shortSuccess =
            IPrimitiveERC20(data.shortToken).burn(shortHolder, shortAmount);
        return success && shortSuccess;
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
}
