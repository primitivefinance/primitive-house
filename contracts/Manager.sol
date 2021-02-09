pragma solidity ^0.7.1;

/**
 * @dev Base manager contract that has non-implemented functions to enforce rules, variables, and invariants.
 */

abstract contract Manager {
    function mintingInvariant() internal virtual returns (uint256, uint256);

    function exerciseInvariant() internal virtual returns (uint256, uint256);

    function settlementInvariant() internal virtual returns (uint256, uint256);
}
