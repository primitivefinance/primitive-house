pragma solidity ^0.7.1;

/**
 * @dev Base manager contract that has non-implemented functions to enforce rules, variables, and invariants.
 */

abstract contract Manager {
    function mintingInvariant(bytes calldata oid)
        external
        view
        virtual
        returns (bool);

    function burningInvariant(bytes calldata oid)
        external
        view
        virtual
        returns (bool);

    function exerciseInvariant(bytes calldata oid)
        external
        view
        virtual
        returns (bool);

    function settlementInvariant(bytes calldata oid)
        external
        view
        virtual
        returns (bool);

    function expiryInvariant(bytes memory oid)
        external
        view
        virtual
        returns (bool);
}
