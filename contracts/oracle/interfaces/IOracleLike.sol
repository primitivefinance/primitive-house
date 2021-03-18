pragma solidity ^0.7.1;

interface IOracleLike {
    function peek(address token) external view returns (uint256);
}
