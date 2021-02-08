pragma solidity ^0.7.1;

import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

interface IWToken is IERC1155 {
    function mint(address token, uint256 amount) external;

    function burn(address token, uint256 amount) external;

    function balanceOfERC20(address token, address user)
        external
        view
        returns (uint256);

    function getUnderlyingToken(uint256 id) external view returns (address);
}
