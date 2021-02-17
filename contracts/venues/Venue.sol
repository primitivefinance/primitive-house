pragma solidity ^0.7.1;

/**
 * @title   The Base Venue contract to facilitate interactions with the House.
 * @author  Primitive
 */

// Open Zeppelin
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

// Internal
import {IERC20} from "../interfaces/IERC20.sol";
import {IHouse} from "../interfaces/IHouse.sol";
import {IWETH} from "../interfaces/IWETH.sol";
import {IMultiToken} from "../interfaces/IMultiToken.sol";
import {BasicERC1155Receiver} from "../utils/BasicERC1155Receiver.sol";

import "hardhat/console.sol";

abstract contract Venue is BasicERC1155Receiver {
    using SafeERC20 for IERC20;

    /**
     * @dev The canonical WETH contract to tokenize ether.
     */
    IWETH internal immutable _weth;

    /**
     * @dev The higher-level option Manager contract.
     */
    IHouse internal immutable _house;

    /**
     * @dev The ERC1155 token this Venue uses to deposit into the House as collateral.
     */
    IMultiToken internal immutable _multiToken;

    /**
     * @dev An array that is set to true when it has been max approved once.
     */
    mapping(address => mapping(address => bool)) internal _isMaxApproved;

    constructor(
        address weth_,
        address house_,
        address multiToken_
    ) {
        _weth = IWETH(weth_);
        _house = IHouse(house_);
        _multiToken = IMultiToken(multiToken_);
        // Approve _multiToken
        IMultiToken(multiToken_).setApprovalForAll(house_, true);
        // Approve _house and _weth
        checkApproved(weth_, house_);
    }

    // ===== Fallback =====

    receive() external payable {
        assert(msg.sender == address(_weth)); // only accept ETH via fallback from the WETH contract
    }

    // ===== Utility =====

    /**
     * @notice  Calls approve for the `spender` to pull `token` from this contract.
     * @dev     Updates `isMaxedApprove` array so that this approval can never be done again.
     */
    function checkApproved(address token, address spender) public {
        if (_isMaxApproved[token][spender]) {
            return;
        } else {
            IERC20(token).approve(spender, uint256(-1));
            _isMaxApproved[token][spender] = true;
        }
    }

    // ===== Wrapped Ether =====

    /**
     * @notice  Calls the `deposit` function on the WETH contract with a sent `msg.value` to it.
     */
    function _wethDeposit() internal {
        if (msg.value > 0) {
            _weth.deposit{value: msg.value}();
        }
    }

    /**
     * @notice  Calls the `withdraw` function on the WETH contract.
     * @dev     Sends withdrawn Ether to the House's original `msg.sender` which is the Account.depositor.
     */
    function _wethWithdraw() internal {
        uint256 balance = IERC20(address(_weth)).balanceOf(address(this));
        if (balance > 0) {
            _weth.withdraw(balance);
            (bool success, ) =
                _house.getExecutingCaller().call{value: balance}(new bytes(0));
            require(success, "Venue: SEND_ETH_BACK");
        }
    }

    // ===== Tokens =====

    /**
     * @notice  Calls the House to pull `token` from the getExecutingCaller() and send them to this contract.
     * @dev     This eliminates the need for users to approve the House and each venue.
     */
    function _requestTokens(address token, uint256 quantity) internal {
        if (quantity > 0) {
            _house.takeTokensFromUser(token, quantity);
        }
    }

    /**
     * @notice  Pushes this contract's balance of `token` to the House's executingCaller().
     * @dev     executingCaller() is the original `msg.sender` of the House's `execute` fn.
     */
    function _tokenWithdraw(address token) internal {
        uint256 balance = IERC20(token).balanceOf(address(this));
        if (balance > 0) {
            IERC20(token).transfer(_house.getExecutingCaller(), balance);
        }
    }

    // ===== MultiTokens =====

    /**
     * @notice  Sends `amount` of ERC20 `token` to a ERC1155 token, then mints the ERC1155 token.
     */
    function _wrapTokenForHouse(address token, uint256 amount) internal {
        if (amount > 0) {
            checkApproved(token, address(_multiToken));
            _multiToken.mint(token, amount);
            console.log("ERC1155 token minted");
            _house.addCollateral(address(_multiToken), uint256(token), amount);
        }
    }

    /**
     * @notice  Pulls `amount` of the ERC1155 token for ERC20 `token` from the _house, then burns the ERC1155.
     */
    function _tokenUnwrapFromHouse(address token, uint256 amount) internal {
        if (amount > 0) {
            _house.removeCollateral(
                address(_multiToken),
                uint256(token),
                amount
            );
            _multiToken.burn(token, amount);
        }
    }

    // ===== Options =====

    /**
     * @notice  Pushes the long and short ERC20 tokens of an option with `oid` to the Multitoken,
     *          then mints a Multitoken with id = `oid`.
     * @dev     Sends the minted Multitoken to the House contract as collateral.
     */
    function _wrapOptionForHouse(bytes32 oid, uint256 amount) internal {
        if (amount > 0) {
            (address long, address short) = _house.getOptionTokens(oid);
            checkApproved(long, address(_multiToken));
            checkApproved(short, address(_multiToken));
            _multiToken.mintOption(oid, long, short, amount);
            console.log("wrapped option token minted");
            _house.addCollateral(address(_multiToken), uint256(oid), amount);
        }
    }

    /**
     * @notice  Pulls the option Multitoken with id = `oid` from the House contract,
     *          then burns the Multitoken to release the long and short option ERC20 tokens to this contract.
     */
    function _optionUnwrapFromHouse(bytes32 oid, uint256 amount) internal {
        if (amount > 0) {
            (address long, address short) = _house.getOptionTokens(oid);
            console.log("removing collateral");
            // Takes out the option collateral token
            _house.removeCollateral(address(_multiToken), uint256(oid), amount);
            console.log("wrapped option token minted");
            _multiToken.burnOption(oid, long, short, amount);
        }
    }

    /**
     * @notice  Mints a batch of ERC1155 tokens with ids = uint(tokens). Adds the batch as collateral.
     */
    function _wrapTokenBatch(address[] memory tokens, uint256[] memory amounts)
        internal
    {
        uint256 tokensLength = tokens.length;
        require(tokensLength == amounts.length, "Venue: ARGS_LENGTHS");

        for (uint256 i = 0; i < tokensLength; i++) {
            uint256 amount = amounts[i];
            address token = tokens[i];
            if (amount > 0) {
                checkApproved(token, address(_multiToken));
            }
        }

        (uint256[] memory ids, uint256[] memory actualAmts) =
            _multiToken.mintBatch(tokens, amounts);
        console.log("wrapped option token minted");
        _house.addBatchCollateral(address(_multiToken), ids, actualAmts);
    }

    /**
     * @notice  Calls the House's minting fn to mint long and short option ERC20s to this contract.
     */
    function _mintOptions(
        bytes32 oid,
        uint256 amount,
        address[] memory receivers,
        bool fromInternal
    ) internal {
        if (amount > 0) {
            _house.mintOptions(oid, amount, receivers);
        }
    }

    /**
     * @notice  Calls the House's exercise fn to exercise long options.
     */
    function _exerciseOptions(
        bytes32 oid,
        uint256 amount,
        address receiver,
        bool fromInternal
    ) internal {
        if (amount > 0) {
            if (fromInternal) {
                (, address quoteToken, , , ) = _house.getParameters(oid);
                // Check the _house can pull quote tokens from this contract
                checkApproved(quoteToken, address(_house));
            }
            _house.exercise(oid, amount, receiver, fromInternal);
        }
    }

    /**
     * @notice  Calls the House's exercise fn to redeem short options.
     */
    function _redeemOptions(
        bytes32 oid,
        uint256 amount,
        address receiver,
        bool fromInternal
    ) internal {
        if (amount > 0) {
            _house.redeem(oid, amount, receiver, fromInternal);
        }
    }

    /**
     * @notice  Calls the House's exercise fn to close an equal amount of long and short option ERC20s.
     */
    function _closeOptions(
        bytes32 oid,
        uint256 amount,
        address receiver,
        bool fromInternal
    ) internal {
        if (amount > 0) {
            _house.close(oid, amount, receiver, fromInternal);
        }
    }

    // ===== View =====

    /**
     * @notice  Gets the WETH address.
     */
    function getWeth() public view returns (address) {
        return address(_weth);
    }

    /**
     * @notice  Gets the House address.
     */
    function getHouse() public view returns (address) {
        return address(_house);
    }

    /**
     * @notice  Gets the MultiToken address.
     */
    function getMultiToken() public view returns (address) {
        return address(_multiToken);
    }

    /**
     * @notice  Gets the boolean for whether or not `token` is approved to be spent by `spender`.
     */
    function getIsMaxApproved(address token, address spender)
        public
        view
        returns (bool)
    {
        return _isMaxApproved[token][spender];
    }
}
