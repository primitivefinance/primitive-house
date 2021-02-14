pragma solidity ^0.7.1;

/**
 * @title The Base Venue contract to facilitate interactions with the House.
 */

// Open Zeppelin
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import {IERC20} from "../interfaces/IERC20.sol";
import {IHouse} from "../interfaces/IHouse.sol";
import {IWETH} from "../interfaces/IWETH.sol";
import {IWToken} from "../interfaces/IWToken.sol";
import {pERC1155Receiver} from "../utils/pERC1155Receiver.sol";

import "hardhat/console.sol";

contract Venue is pERC1155Receiver {
    using SafeERC20 for IERC20;

    IWETH public immutable weth;
    IHouse public immutable house;
    IWToken public immutable wToken;

    mapping(address => mapping(address => bool)) public isMaxApproved;

    constructor(
        address weth_,
        address house_,
        address wToken_
    ) {
        weth = IWETH(weth_);
        house = IHouse(house_);
        wToken = IWToken(wToken_);
        // Approve wrap token
        IWToken(wToken_).setApprovalForAll(house_, true);
        // Approve house and weth
        checkApproved(weth_, house_);
    }

    receive() external payable {
        assert(msg.sender == address(weth)); // only accept ETH via fallback from the WETH contract
    }

    // ===== Utility =====

    function checkApproved(address token, address spender) public {
        if (isMaxApproved[token][spender]) {
            return;
        } else {
            IERC20(token).approve(spender, uint256(-1));
            isMaxApproved[token][spender] = true;
        }
    }

    function _wethDeposit() internal {
        if (msg.value > 0) {
            weth.deposit{value: msg.value}();
        }
    }

    function _wethWithdraw() internal {
        uint256 balance = IERC20(address(weth)).balanceOf(address(this));
        if (balance > 0) {
            weth.withdraw(balance);
            (bool success, ) =
                house.getExecutingCaller().call{value: balance}(new bytes(0));
            require(success, "Venue: SEND_ETH_BACK");
        }
    }

    // ===== Tokens =====
    function _requestTokens(address token, uint256 quantity) internal {
        if (quantity > 0) {
            house.takeTokensFromUser(token, quantity);
        }
    }

    function _tokenWithdraw(address token) internal {
        uint256 balance = IERC20(token).balanceOf(address(this));
        if (balance > 0) {
            IERC20(token).transfer(house.getExecutingCaller(), balance);
        }
    }

    // ===== Wrapped Tokens =====

    /**
     * @notice  Sends `amount` of `token` to a wrapped token, then mints the wrapped token.
     */
    function _wrapTokenForHouse(address token, uint256 amount) internal {
        if (amount > 0) {
            checkApproved(token, address(wToken));
            wToken.mint(token, amount);
            console.log("wrapped token minted");
            house.addCollateral(address(wToken), uint256(token), amount);
        }
    }

    /**
     * @notice  Pulls `amount` of the wrapped token for `token` from the house, then burns the wrapped token.
     */
    function _tokenUnwrapFromHouse(address token, uint256 amount) internal {
        if (amount > 0) {
            house.removeCollateral(address(wToken), uint256(token), amount);
            wToken.burn(token, amount);
        }
    }

    // ===== Options =====

    function _wrapOptionForHouse(bytes32 oid, uint256 amount) internal {
        if (amount > 0) {
            (address long, address short) = house.getOptionTokens(oid);
            checkApproved(long, address(wToken));
            checkApproved(short, address(wToken));
            wToken.mintOption(oid, long, short, amount);
            console.log("wrapped option token minted");
            house.addCollateral(address(wToken), uint256(oid), amount);
        }
    }

    function _optionUnwrapFromHouse(bytes32 oid, uint256 amount) internal {
        if (amount > 0) {
            (address long, address short) = house.getOptionTokens(oid);
            console.log("removing collateral");
            // Takes out the option collateral token
            house.removeCollateral(address(wToken), uint256(oid), amount);
            console.log("wrapped option token minted");
            wToken.burnOption(oid, long, short, amount);
        }
    }

    function _exerciseOptions(
        bytes32 oid,
        uint256 amount,
        address receiver,
        bool fromInternal
    ) internal {
        if (amount > 0) {
            (address long, ) = house.getOptionTokens(oid);
            if (fromInternal) {
                (, address quoteToken, , , ) = house.getParameters(oid);
                // Check the house can pull quote tokens from this contract
                checkApproved(quoteToken, address(house));
            }
            house.exercise(oid, amount, receiver, fromInternal);
        }
    }

    function _redeemOptions(
        bytes32 oid,
        uint256 amount,
        address receiver,
        bool fromInternal
    ) internal {
        if (amount > 0) {
            (address long, address short) = house.getOptionTokens(oid);
            house.redeem(oid, amount, receiver, fromInternal);
        }
    }

    function _closeOptions(
        bytes32 oid,
        uint256 amount,
        address receiver,
        bool fromInternal
    ) internal {
        if (amount > 0) {
            (address long, address short) = house.getOptionTokens(oid);
            house.close(oid, amount, receiver, fromInternal);
        }
    }

    // ===== Actions =====

    function _mintOptions(
        address optionAddress,
        uint256 quantity,
        address longReceiver,
        address shortReceiver
    ) internal {
        if (quantity > 0) {}
    }

    // ===== View =====
}
