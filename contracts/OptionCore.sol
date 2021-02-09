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

contract OptionCore is OptionData {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    uint8 internal constant SUCCESS_CODE = uint8(0);
    uint8 internal constant FAILURE_CODE = uint8(1);
    uint8 internal constant MINTING_FAILURE = uint8(22);

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

    constructor() {}

    // ===== Option Core =====

    // ERR CODES:
    // 0 - Success
    // 1 - Unknown failure
    // 22 - Minting invariant failure

    /**
     * @dev Mint the `oid` option tokens to `receivers` using the mintingInvariant function.
     */
    function dangerousMint(bytes memory oid, address[] memory receivers)
        public
        returns (uint256)
    {
        // mint invariant -> replace with a fn from option manager
        (uint256 mintInvariant, uint256 mintAmount) =
            IManager(msg.sender).mintingInvariant();
        if (mintInvariant == uint256(0)) {
            uint256 code = _internalMint(oid, mintAmount, receivers);
            emit OptionsMinted(
                msg.sender,
                mintAmount,
                receivers[0],
                receivers[1]
            );
            return code;
        } else {
            return MINTING_FAILURE;
        }
    }

    /**
     * @dev Mint the `oid` option tokens to `receivers` using the mintingInvariant function.
     */
    function dangerousBatchMint(
        bytes[] memory oidBatch,
        address[] memory receiverBatch
    ) public returns (uint256) {
        uint256 oidBatchLength = oidBatch.length;
        uint256 receiverBatchLength = receiverBatch.length;
        require(oidBatchLength == receiverBatchLength.div(2), "err length");
        uint256[] memory successCodes;
        uint256 startIndex;
        for (uint256 i = 0; i < oidBatchLength; i++) {
            bytes memory oidSingle = oidBatch[i];
            address[] memory receivers = new address[](2);
            receivers[0] = receiverBatch[i + startIndex];
            receivers[1] = receiverBatch[i + startIndex + 1];
            // mint invariant -> replace with a fn from option manager
            uint256 mintInvariant = uint256(0);
            uint256 mintAmount = mintInvariant.add(1); // should be a value returned by minting invariant
            if (mintInvariant == uint256(0)) {
                uint256 code = _internalMint(oidSingle, mintAmount, receivers);
                emit OptionsMinted(
                    msg.sender,
                    mintAmount,
                    receivers[0],
                    receivers[1]
                );
                successCodes[i] = code;
            }

            startIndex++;
        }

        return
            successCodes.length == oidBatchLength
                ? SUCCESS_CODE
                : MINTING_FAILURE;
    }

    function _internalMint(
        bytes memory oid,
        uint256 amount,
        address[] memory receivers
    ) internal returns (uint256) {
        TokenData memory data = _tokenData[oid];
        address longReceiver = receivers[0];
        address shortReceiver = receivers[1];
        bool success =
            IPrimitiveERC20(data.longToken).mint(longReceiver, amount);
        bool shortSuccess =
            IPrimitiveERC20(data.shortToken).mint(shortReceiver, amount);
        return success && shortSuccess ? SUCCESS_CODE : FAILURE_CODE;
    }

    /**
     * @dev Burn the `oid` option tokens using the burningInvariant function.
     */
    function dangerousBurn(bytes memory oid, address[] memory accounts)
        public
        returns (uint256)
    {
        // burn invariant -> replace with a fn from option manager
        uint256 burnInvariant = uint256(0);
        uint256[] memory burnAmounts = new uint256[](2);
        burnAmounts[0] = burnInvariant.add(1);
        burnAmounts[1] = burnInvariant.add(1);
        if (burnInvariant == uint256(0)) {
            uint256 code = _internalBurn(oid, burnAmounts, accounts);
            emit OptionsBurned(
                msg.sender,
                burnAmounts[0],
                burnAmounts[1],
                accounts[0],
                accounts[1]
            );
            return code;
        } else {
            return MINTING_FAILURE;
        }
    }

    /**
     * @dev Burn the `oid` option tokens using the burningInvariant function.
     */
    function dangerousBatchBurn(
        bytes[] memory oidBatch,
        address[] memory accounts
    ) public returns (uint256) {
        uint256 oidBatchLength = oidBatch.length;
        uint256 accountsLength = accounts.length;
        require(oidBatchLength == accountsLength.div(2), "err length");
        uint256[] memory successCodes;
        uint256 startIndex;
        for (uint256 i = 0; i < oidBatchLength; i++) {
            bytes memory oidSingle = oidBatch[i];
            address[] memory receivers = new address[](2);
            receivers[0] = accounts[i + startIndex];
            receivers[1] = accounts[i + startIndex + 1];
            // burn invariant -> replace with a fn from option manager
            uint256 burnInvariant = uint256(0);
            uint256[] memory burnAmounts = new uint256[](2);
            burnAmounts[0] = burnInvariant.add(1);
            burnAmounts[1] = burnInvariant.add(1);
            if (burnInvariant == uint256(0)) {
                uint256 code = _internalBurn(oidSingle, burnAmounts, accounts);
                emit OptionsBurned(
                    msg.sender,
                    burnAmounts[0],
                    burnAmounts[1],
                    accounts[0],
                    accounts[1]
                );
                successCodes[i] = code;
            }

            startIndex++;
        }
        return
            successCodes.length == oidBatchLength
                ? SUCCESS_CODE
                : MINTING_FAILURE;
    }

    function _internalBurn(
        bytes memory oid,
        uint256[] memory amounts,
        address[] memory accounts
    ) internal returns (uint256) {
        TokenData memory data = _tokenData[oid];
        address longHolder = accounts[0];
        address shortHolder = accounts[1];
        uint256 longAmount = amounts[0];
        uint256 shortAmount = amounts[1];
        bool success =
            IPrimitiveERC20(data.longToken).burn(longHolder, longAmount);
        bool shortSuccess =
            IPrimitiveERC20(data.shortToken).burn(shortHolder, shortAmount);
        return success && shortSuccess ? SUCCESS_CODE : FAILURE_CODE;
    }

    // ===== View =====
}
