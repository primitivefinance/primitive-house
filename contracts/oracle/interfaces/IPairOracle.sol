pragma solidity ^0.7.1;

interface IPairOracle {
    function getLPTokenPrice(address pair)
        external
        returns (uint128 quote, uint32 ts);

    function getPrice0TWAP(address pair) external view returns (uint256);

    function getPrice1TWAP(address pair) external view returns (uint256);
}
