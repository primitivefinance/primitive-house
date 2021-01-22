pragma solidity >=0.6.2;

interface IVenue {

    // adding liquidity returns quantity of lp tokens minted
    function deposit(bytes calldata params) external returns (uint);

    // removing liquidity returns quantities of tokens withdrawn
    function withdraw(uint amount) external returns(address[] memory tokens, uint[] memory amounts);

    function pool() external view returns (address);

    function swap(address[] calldata path, uint quantity, uint maxPremium) external returns (uint[] memory amounts); 
}