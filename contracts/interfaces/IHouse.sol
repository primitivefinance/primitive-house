pragma solidity >=0.6.2;

interface IHouse {
    function doublePosition(address depositor, address longOption, uint quantity, address router, bytes calldata params) external;
}
