pragma solidity ^0.7.1;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IPrimitiveERC20 is IERC20 {
    function initialize(string calldata name_, string calldata symbol_)
        external;

    function mint(address to, uint256 value) external returns (bool);

    function burn(address from, uint256 value) external returns (bool);

    function name() external view returns (string memory);

    function symbol() external view returns (string memory);

    function decimals() external pure returns (uint8);

    function DOMAIN_SEPARATOR() external view returns (bytes32);

    function PERMIT_TYPEHASH() external pure returns (bytes32);

    function nonces(address owner) external view returns (uint256);

    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
}
