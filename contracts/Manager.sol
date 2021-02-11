pragma solidity ^0.7.1;

/**
 * @dev Base manager contract that has non-implemented functions to enforce rules, variables, and invariants.
 */

abstract contract Manager {
    function mintingInvariant(bytes calldata oid, uint256 amount)
        external
        virtual
        returns (bool, uint256);

    function burningInvariant(bytes calldata oid, uint256[] calldata amounts)
        external
        view
        virtual
        returns (bool);

    function exerciseInvariant(bytes calldata oid, uint256[] calldata amounts)
        external
        view
        virtual
        returns (bool);

    function settlementInvariant(bytes calldata oid)
        external
        view
        virtual
        returns (bool);

    function closeInvariant(bytes calldata oid, uint256[] calldata amounts)
        external
        virtual
        returns (bool);

    function expiryInvariant(bytes memory oid)
        external
        view
        virtual
        returns (bool);
}
