pragma solidity ^0.7.1;

interface IRegistry {
    function createOption(
        address baseToken,
        address quoteToken,
        uint256 strikePrice,
        uint32 expiry,
        bool isCall
    )
        external
        returns (
            bytes32,
            address,
            address
        );

    function getTokenData(bytes32 oid) external view returns (address, address);

    function getParameters(bytes32 oid)
        external
        view
        returns (
            address,
            address,
            uint256,
            uint32,
            uint8
        );

    function getOIdFromParameters(
        address baseToken,
        address quoteToken,
        uint256 strikePrice,
        uint32 expiry,
        bool isCall
    ) external view returns (bytes32);

    function getOptionIdFromAddress(address option)
        external
        view
        returns (bytes32);

    // ===== Pure =====
    function generateType(bool isCall)
        external
        pure
        returns (uint8, string calldata);

    function CALL() external pure returns (uint8);

    function PUT() external pure returns (uint8);
}
