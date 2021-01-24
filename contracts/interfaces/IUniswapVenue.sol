// SPDX-License-Identifier: MIT
pragma solidity >=0.6.2;

import {
    IUniswapV2Router02
} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import {
    IUniswapV2Factory
} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import {
    IOption,
    IERC20
} from "@primitivefi/contracts/contracts/option/interfaces/IOption.sol";

interface IUniswapVenue {
    // ==== Flash Functions ====

    function flashMintShortOptionsThenSwap(
        address optionAddress,
        uint256 flashLoanQuantity,
        uint256 maxPremium,
        address to
    ) external payable returns (uint256, uint256);

    function flashCloseLongOptionsThenSwap(
        address optionAddress,
        uint256 flashLoanQuantity,
        uint256 minPayout,
        address to
    ) external returns (uint256, uint256);

    // ==== View ====

    function router() external view returns (IUniswapV2Router02);

    function factory() external view returns (IUniswapV2Factory);

    function getName() external view returns (string memory);

    function getVersion() external view returns (string memory);

    function getOpenPremium(IOption optionToken, uint256 quantityLong)
        external
        view
        returns (uint256, uint256);

    function getClosePremium(IOption optionToken, uint256 quantityShort)
        external
        view
        returns (uint256, uint256);

    function uniswapV2Call(
        address sender,
        uint256 amount0,
        uint256 amount1,
        bytes calldata data
    ) external;
}
