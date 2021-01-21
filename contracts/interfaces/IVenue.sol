pragma solidity >=0.6.2;

interface IVenue {

    // adding liquidity returns quantity of lp tokens minted
    function deposit() external returns (uint);

    // removing liquidity returns quantities of tokens withdrawn
    function withdraw() external returns(uint[] memory);
}