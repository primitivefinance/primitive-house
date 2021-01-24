pragma solidity >=0.6.2;

interface IHouse {
    function doublePosition(
        address depositor,
        address longOption,
        uint256 quantity,
        address router,
        bytes calldata params
    ) external;

    function virtualOptions(address optionAddress)
        external
        view
        returns (address);
}
