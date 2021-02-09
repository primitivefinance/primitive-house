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

    event OptionsMinted(
        address indexed from,
        uint256 amount,
        address indexed longReceiver,
        address indexed shortReceiver
    );

    event OptionsBurned(
        address indexed from,
        uint256 longAmount,
        uint256 shortAmount,
        address indexed longReceiver,
        address indexed shortReceiver
    );

    IManager internal immutable _manager;

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
        uint256 amount,
        address[] memory receivers
    ) public override returns (bool) {
        // mint invariant -> replace with a fn from option manager
        bool success = _manager.mintingInvariant(oid);
        require(success, "Core: MINT_FAIL");
        _internalMint(oid, amount, receivers);
        emit OptionsMinted(msg.sender, amount, receivers[0], receivers[1]);
        return success;
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
    function dangerousBurn(
        bytes memory oid,
        uint256[] memory amounts,
        address[] memory accounts
    ) public override returns (bool) {
        // burn invariant -> replace with a fn from option manager
        bool burnInvariant = _manager.burningInvariant(oid);
        require(burnInvariant, "Core: BURN_FAIL");

        if (amounts[1] == uint256(0)) {
            // if no short tokens are being burned, its an exercise.
            bool exerciseInvariant = _manager.exerciseInvariant(oid);
            // if exercise invariant is not cleared, returned the bubbled up error code.
            require(exerciseInvariant, "Core: EXERCISE_FAIL");
        }

        if (amounts[0] == uint256(0)) {
            // if no long tokens are being burned, its a settlement
            bool settleInvariant = _manager.settlementInvariant(oid);
            // if settlement invariant is not cleared, returned the bubbled up error code.
            require(settleInvariant, "Core: SETTLE_FAIL");
        }

        _internalBurn(oid, amounts, accounts);
        emit OptionsBurned(
            msg.sender,
            amounts[0],
            amounts[1],
            accounts[0],
            accounts[1]
        );
        return burnInvariant;
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

    // ===== View =====
}
