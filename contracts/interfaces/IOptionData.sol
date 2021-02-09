pragma solidity ^0.7.1;

interface IOptionData {
    function createOption(
        address baseToken,
        address quoteToken,
        uint256 strikePrice,
        uint8 expiry,
        bool isCall
    )
        external
        returns (
            bytes calldata,
            address,
            address
        );

    function getTokenData(bytes calldata id)
        external
        view
        returns (address, address);

    function getParameters(bytes calldata id)
        external
        view
        returns (
            address,
            address,
            uint256,
            uint8,
            uint8
        );

    // ===== Pure =====
    function generateType(bool isCall)
        external
        pure
        returns (uint8, string calldata);
}
