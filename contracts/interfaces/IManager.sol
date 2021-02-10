pragma solidity ^0.7.1;

interface IManager {
    function mintingInvariant(bytes calldata oid, uint256 amount)
        external
        view
        returns (bool, uint256);

    function burningInvariant(bytes calldata oid, uint256[] calldata amounts)
        external
        view
        returns (bool);

    function exerciseInvariant(bytes calldata oid, uint256[] calldata amounts)
        external
        view
        returns (bool);

    function settlementInvariant(bytes calldata oid)
        external
        view
        returns (bool);

    function closeInvariant(bytes calldata oid, uint256[] calldata amounts)
        external
        view
        returns (bool);

    function expiryInvariant(bytes memory oid) external view returns (bool);
}
