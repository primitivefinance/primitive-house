pragma solidity 0.6.2;

///
/// @title   Library for business logic for connecting Uniswap V2 Protocol functions with Primitive V1.
/// @notice  Primitive Router Lib - @primitivefi/v1-connectors@v1.3.0
/// @author  Primitive
///

// Primitive
import {
    IOption
} from "@primitivefi/contracts/contracts/option/interfaces/ITrader.sol";
import {
    TraderLib,
    IERC20
} from "@primitivefi/contracts/contracts/option/libraries/TraderLib.sol";
import {IWETH} from "../interfaces/IWETH.sol";
// Open Zeppelin
import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

library RouterLib {
    using SafeERC20 for IERC20; // Reverts when `transfer` or `transferFrom` erc20 calls don't return proper data
    using SafeMath for uint256; // Reverts on math underflows/overflows

    /**
     * @dev    Calculates the proportional quantity of long option tokens per short option token.
     * @notice For each long option token, there is quoteValue / baseValue quantity of short option tokens.
     */
    function getProportionalLongOptions(
        IOption optionToken,
        uint256 quantityShort
    ) internal view returns (uint256) {
        uint256 quantityLong =
            quantityShort.mul(optionToken.getBaseValue()).div(
                optionToken.getQuoteValue()
            );

        return quantityLong;
    }

    /**
     * @dev    Calculates the proportional quantity of short option tokens per long option token.
     * @notice For each short option token, there is baseValue / quoteValue quantity of long option tokens.
     */
    function getProportionalShortOptions(
        IOption optionToken,
        uint256 quantityLong
    ) internal view returns (uint256) {
        uint256 quantityShort =
            quantityLong.mul(optionToken.getQuoteValue()).div(
                optionToken.getBaseValue()
            );

        return quantityShort;
    }

    /**
     * @dev Deposits amount of ethers into WETH contract. Then sends WETH to "to".
     * @param to The address to send WETH ERC-20 tokens to.
     */
    function safeTransferETHFromWETH(
        IWETH weth,
        address to,
        uint256 amount
    ) internal {
        // Deposit the ethers received from amount into the WETH contract.
        weth.deposit.value(amount)();

        // Send WETH.
        weth.transfer(to, amount);
    }

    /**
     * @dev Unwraps WETH to withrdaw ethers, which are then sent to the "to" address.
     * @param to The address to send withdrawn ethers to.
     * @param amount The amount of WETH to unwrap.
     */
    function safeTransferWETHToETH(
        IWETH weth,
        address to,
        uint256 amount
    ) internal {
        // Withdraw ethers with weth.
        weth.withdraw(amount);
        // Send ether.
        (bool success, ) = to.call.value(amount)("");
        // Revert is call is unsuccessful.
        require(success, "PrimitiveV1: ERR_SENDING_ETHER");
    }
}
