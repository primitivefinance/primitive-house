pragma solidity ^0.7.1;

interface IFactory {
    function deployClone(string calldata name, string calldata symbol)
        external
        returns (address);

    function getTemplate() external view returns (address);
}
