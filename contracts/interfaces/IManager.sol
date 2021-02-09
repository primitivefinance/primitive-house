pragma solidity ^0.7.1;

interface IManager {
    function mintingInvariant(bytes calldata oid) external view returns (bool);

    function burningInvariant(bytes calldata oid) external view returns (bool);

    function exerciseInvariant(bytes calldata oid) external view returns (bool);

    function settlementInvariant(bytes calldata oid)
        external
        view
        returns (bool);

    function expiryInvariant(bytes memory oid) external view returns (bool);
}
