pragma solidity ^0.7.1;

interface ISwapVenue {
    function addShortLiquidityWithUnderlying(
      bytes32 oid,
      uint256 amount,
      uint256 deadline
    ) external;

    function addLongLiquidityWithUnderlying(
      bytes32 oid,
      uint256 amount,
      uint256 deadline
    ) external;
}
