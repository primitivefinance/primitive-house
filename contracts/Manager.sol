// SPDX-License-Identifier: MIT
pragma solidity ^0.7.1;
pragma experimental ABIEncoderV2;

/**
 * @title   The Primitive House -> Manages collateral, leverages liquidity.
 * @author  Primitive
 */

// Open Zeppelin
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {
    ReentrancyGuard
} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

// Primitive
import {ICore} from "./interfaces/ICore.sol";
import {IFlash} from "./interfaces/IFlash.sol";

// Internal
import {IWETH} from "./interfaces/IWETH.sol";
import {SafeMath} from "./libraries/SafeMath.sol";

import "hardhat/console.sol";

abstract contract Manager is Ownable {
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
     * @dev The contract with core option logic.
     */
    ICore internal _core;

    constructor(address optionCore_) {
        _core = ICore(optionCore_);
    }

    function setCore(address core_) public onlyOwner {
        _core = ICore(core_);
    }

    // ====== Transfers ======

    /**
     * @notice  Transfer ERC20 tokens from `msg.sender` to this contract.
     * @param   token The address of the ERC20 token.
     * @param   amount The amount of ERC20 tokens to transfer.
     * @return  The actual amount of `token` sent in to this contract.
     */
    function _pullToken(address token, uint256 amount)
        internal
        returns (uint256)
    {
        uint256 prevBal = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        uint256 postBal = IERC20(token).balanceOf(address(this));
        return postBal.sub(prevBal);
    }

    /**
     * @notice  Transfer ERC1155 tokens from `msg.sender` to this contract.
     * @param   token The ERC1155 token to call.
     * @param   wid The ERC1155 token id to transfer.
     * @param   amount The amount of ERC1155 with `wid` to transfer.
     * @return  The actual amount of `token` sent in to this contract.
     */
    function _pullWrappedToken(
        address token,
        uint256 wid,
        uint256 amount
    ) internal returns (uint256) {
        uint256 prevBal = IERC1155(token).balanceOf(address(this), wid);
        IERC1155(token).safeTransferFrom(
            msg.sender,
            address(this),
            wid,
            amount,
            ""
        );
        uint256 postBal = IERC1155(token).balanceOf(address(this), wid);
        return postBal.sub(prevBal);
    }

    /**
     * @notice  Transfer multiple ERC1155 tokens from `msg.sender` to this contract.
     * @param   token The ERC1155 token to call.
     * @param   wids The ERC1155 token ids to transfer.
     * @param   amounts The amounts of ERC1155 tokens to transfer.
     * @return  The actual amount of `token` sent in to this contract.
     */
    function _pullBatchWrappedTokens(
        address token,
        uint256[] memory wids,
        uint256[] memory amounts
    ) internal returns (uint256) {
        IERC1155(token).safeBatchTransferFrom(
            msg.sender,
            address(this),
            wids,
            amounts,
            ""
        );
        return uint256(-1);
    }

    // ===== Option Core =====

    /**
     * @notice  Mints options to the receiver addresses.
     * @param   oid The option data id used to fetch option related data.
     * @param   requestAmt The requestAmt of options requested to be minted.
     * @param   receivers The long option ERC20 receiver, and short option ERC20 receiver.
     * @return  Whether or not the mint succeeded.
     */
    function mintOptions(
        bytes32 oid,
        uint256 requestAmt,
        address[] memory receivers
    ) public returns (bool) {
        // Execute the mint
        _core.dangerousMint(oid, requestAmt, receivers);
        return _onAfterMint(oid, requestAmt, receivers);
    }

    function exercise(
        bytes32 oid,
        uint256 amount,
        address receiver
    ) public returns (bool) {
        _onBeforeExercise(oid, amount, receiver);
        address sender = _getExecutingSender();
        // Burn long tokens
        (uint256 lessBase, uint256 plusQuote) =
            _core.dangerousExercise(oid, sender, amount);

        return _onAfterExercise(oid, amount, receiver, lessBase, plusQuote);
    }

    function redeem(
        bytes32 oid,
        uint256 amount,
        address receiver
    ) public returns (bool) {
        (uint256 minOutputQuote, uint256 quoteClaim) =
            _onBeforeRedeem(oid, amount, receiver);
        address sender = _getExecutingSender();
        // Burn long tokens
        uint256 lessQuote =
            _core.dangerousRedeem(
                oid,
                sender,
                amount,
                minOutputQuote,
                quoteClaim
            );

        return _onAfterRedeem(oid, amount, receiver, lessQuote);
    }

    function close(
        bytes32 oid,
        uint256 amount,
        address receiver
    ) public returns (bool) {
        _onBeforeClose(oid, amount, receiver);
        address sender = _getExecutingSender();
        // Burn long tokens
        uint256 lessBase = _core.dangerousClose(oid, sender, amount);
        return _onAfterClose(oid, amount, receiver, lessBase);
    }

    // ===== Virtual Hooks =====

    /**
     * @notice  Hook to be implemented by higher-level Manager contract after minting occurs.
     */
    function _onAfterMint(
        bytes32 oid,
        uint256 amount,
        address[] memory receivers
    ) internal virtual returns (bool);

    /*
     * @notice Hook to be implemented by higher-level Manager contract before exercising occurs.
     */
    function _onBeforeExercise(
        bytes32 oid,
        uint256 amount,
        address receiver
    ) internal virtual returns (bool);

    /**
     * @notice  Hook to be implemented by higher-level Manager contract after exercising occurs.
     */
    function _onAfterExercise(
        bytes32 oid,
        uint256 amount,
        address receiver,
        uint256 lessBase,
        uint256 plusQuote
    ) internal virtual returns (bool);

    /**
     * @notice  Hook to be implemented by higher-level Manager contract before redemption occurs.
     */
    function _onBeforeRedeem(
        bytes32 oid,
        uint256 amount,
        address receiver
    ) internal virtual returns (uint256, uint256);

    /**
     * @notice  Hook to be implemented by higher-level Manager contract after redemption occurs.
     */
    function _onAfterRedeem(
        bytes32 oid,
        uint256 amount,
        address receiver,
        uint256 lessQuote
    ) internal virtual returns (bool);

    /**
     * @notice  Hook to be implemented by higher-level Manager contract before closing occurs.
     */
    function _onBeforeClose(
        bytes32 oid,
        uint256 amount,
        address receiver
    ) internal virtual returns (bool);

    /**
     * @notice  Hook to be implemented by higher-level Manager contract after closing occurs.
     */
    function _onAfterClose(
        bytes32 oid,
        uint256 amount,
        address receiver,
        uint256 lessBase
    ) internal virtual returns (bool);

    // ===== View =====

    function getCore() public view returns (address) {
        return address(_core);
    }

    // === Registry ===

    function getOptionTokens(bytes32 oid)
        public
        view
        returns (address, address)
    {
        return _core.getTokenData(oid);
    }

    function getParameters(bytes32 oid)
        public
        view
        returns (
            address,
            address,
            uint256,
            uint32,
            uint8
        )
    {
        return _core.getParameters(oid);
    }

    function getOptionBalances(bytes32 oid, address account)
        public
        view
        returns (uint256[] memory)
    {
        return _core.getOptionBalances(oid, account);
    }

    // === Virtual View Hooks ===

    function notExpired(bytes32 oid) public view returns (bool) {
        return _notExpired(oid);
    }

    function _notExpired(bytes32 oid) internal view virtual returns (bool);

    function getExecutingSender() public view returns (address) {
        return _getExecutingSender();
    }

    function _getExecutingSender() internal view virtual returns (address);
}
