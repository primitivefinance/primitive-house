pragma solidity >=0.6.2;

import {IVenue} from "./interfaces/IVenue.sol";
import {
    IOption
} from "@primitivefi/contracts/contracts/option/interfaces/IOption.sol";

abstract contract Venue {
    // adding liquidity returns quantity of lp tokens minted
    function deposit(
        address[] calldata options,
        uint256[] calldata maxAmounts,
        uint256[] calldata minAmounts,
        address receiver,
        uint256 deadline
    ) external virtual returns (uint256);

    // removing liquidity returns quantities of tokens withdrawn
    function withdraw(
        address[] calldata options,
        uint256[] calldata quantities,
        uint256[] calldata minAmounts,
        address receiver,
        uint256 deadline
    ) external virtual returns (uint256);

    function pool(address option) external view virtual returns (address);

    /* function swap(
        address[] calldata path,
        uint256 quantity,
        uint256 maxPremium
    ) external virtual returns (uint256[] memory amounts); */

    // buy options
    function swapFromUnderlyingToOptions(
        IOption[] calldata options,
        uint256[] calldata quantities,
        uint256[] calldata maxAmounts
    ) external virtual returns (bool);

    function swapFromETHToOptions(
        IOption[] calldata options,
        uint256[] calldata quantities,
        uint256[] calldata maxAmounts
    ) external payable virtual returns (bool);

    // sell options
    function swapFromOptionsToUnderlying(
        IOption[] calldata options,
        uint256[] calldata quantities,
        uint256[] calldata minAmounts
    ) external virtual returns (bool);

    function swapFromOptionsToETH(
        IOption[] calldata options,
        uint256[] calldata quantities,
        uint256[] calldata minAmounts
    ) external virtual returns (bool);

    // write options
    function writeOptions(
        IOption[] calldata options,
        uint256[] calldata quantities,
        uint256[] calldata minAmounts
    ) external virtual returns (bool);

    /* function writeETHOptionsForETH(
        IOption[] calldata options,
        uint256[] calldata minAmounts
    ) external payable virtual returns (uint256[] memory amounts); */
}
