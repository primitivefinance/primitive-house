pragma solidity ^0.7.1;

/**
 * @title   An ERC-1155 Wrapper contract for ERC-20 tokens.
 * @author  Primitive
 */

import {
    ERC1155,
    SafeMath
} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import {
    ReentrancyGuard
} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IWToken} from "./interfaces/IWToken.sol";

contract wToken is ERC1155("wToken"), ReentrancyGuard, IWToken {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    // ===== Token Operations =====

    function mint(address token, uint256 amount)
        external
        override
        nonReentrant
    {
        // store current balance to check against the balance after tokens have been pulled.
        uint256 prevBal = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        uint256 postBal = IERC20(token).balanceOf(address(this));
        uint256 balanceDiff = postBal.sub(prevBal);
        uint256 id = uint256(token);
        _mint(msg.sender, id, balanceDiff, "");
    }

    function burn(address token, uint256 amount)
        external
        override
        nonReentrant
    {
        uint256 id = uint256(token);
        _burn(msg.sender, id, amount);
        IERC20(token).safeTransfer(msg.sender, amount);
    }

    /**
     * @notice  Transfers both long and short option ERC20s from `oid` to a wrapped token with wid = oid.
     */
    function mintOption(
        bytes32 oid,
        address long,
        address short,
        uint256 amount
    ) external override nonReentrant {
        // store current balance to check against the balance after tokens have been pulled.
        uint256 prevBal = IERC20(long).balanceOf(address(this));
        IERC20(long).safeTransferFrom(msg.sender, address(this), amount);
        uint256 postBal = IERC20(long).balanceOf(address(this));
        uint256 balanceDiff = postBal.sub(prevBal);

        uint256 prevBalShort = IERC20(short).balanceOf(address(this));
        IERC20(short).safeTransferFrom(msg.sender, address(this), amount);
        uint256 postBalShort = IERC20(short).balanceOf(address(this));
        uint256 balanceDiffShort = postBalShort.sub(prevBalShort);
        require(balanceDiff == balanceDiffShort, "wToken: MISMATCH_AMTS");
        _mint(msg.sender, uint256(oid), balanceDiff, "");
    }

    function burnOption(
        bytes32 oid,
        address long,
        address short,
        uint256 amount
    ) external override nonReentrant {
        // Burns the wrapped tokens from `msg.sender`, then sends long and short to `msg.sender`.
        _burn(msg.sender, uint256(oid), amount);
        IERC20(long).safeTransfer(msg.sender, amount);
        IERC20(short).safeTransfer(msg.sender, amount);
    }

    // ===== ERC20 Conversion =====

    function getUnderlyingToken(uint256 id)
        external
        view
        override
        returns (address)
    {
        address token = address(id);
        require(uint256(token) == id, "Primitive: ID_OVERFLOW");
        return token;
    }

    function balanceOfERC20(address token, address user)
        external
        view
        override
        returns (uint256)
    {
        return balanceOf(user, uint256(token));
    }
}
