pragma solidity ^0.7.1;

interface IManager {
    function mintingInvariant() external returns (uint256, uint256);

    function exerciseInvariant() external returns (uint256, uint256);

    function settlementInvariant() external returns (uint256, uint256);
}
