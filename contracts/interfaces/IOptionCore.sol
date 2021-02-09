pragma solidity ^0.7.1;
pragma experimental ABIEncoderV2;

interface IOptionCore {
    function dangerousMint(bytes calldata oid, address[] calldata receivers)
        external
        returns (uint256);

    function dangerousBatchMint(
        bytes[] calldata oidBatch,
        address[] calldata receiverBatch
    ) external returns (uint256);

    function dangerousBurn(bytes calldata oid, address[] calldata accounts)
        external
        returns (uint256);

    function dangerousBatchBurn(
        bytes[] calldata oidBatch,
        address[] calldata accounts
    ) external returns (uint256);
}
