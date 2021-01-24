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

interface ISushiSwapVenue {
    function getApprovedPool(address option) external returns (address);

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

    // ==== View ====

    function router() external view returns (IUniswapV2Router02);

    function factory() external view returns (IUniswapV2Factory);

    function getName() external view returns (string memory);

    function getVersion() external view returns (string memory);
}
