pragma solidity ^0.7.1;

interface IManager {
    function getExecutingCaller() external view returns (address);

    function getExecutingVenue() external view returns (address);
}
