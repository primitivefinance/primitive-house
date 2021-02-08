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

contract WToken is ERC1155("WToken"), ReentrancyGuard, IWToken {
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
