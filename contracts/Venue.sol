pragma solidity >=0.6.2;

import {IVenue} from "./interfaces/IVenue.sol";



abstract contract Venue {

    // adding liquidity returns quantity of lp tokens minted
    function deposit() external virtual returns (uint);

    // removing liquidity returns quantities of tokens withdrawn
    function withdraw(uint amount) external virtual returns(address[] memory tokens, uint[] memory amounts);

    function pool(address option) external view virtual returns (address);

    function swap(address[] calldata path, uint quantity, uint maxPremium) external virtual returns (uint[] memory amounts); 
}