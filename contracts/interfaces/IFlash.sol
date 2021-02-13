// SPDX-License-Identifier: MIT

pragma solidity ^0.7.1;

interface IFlash {
    function primitiveFlash(
        address receiver,
        uint256 amount,
        bytes calldata data
    ) external;
}