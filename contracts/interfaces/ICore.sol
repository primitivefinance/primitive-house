pragma solidity ^0.7.1;
pragma experimental ABIEncoderV2;

import {IRegistry} from "./IRegistry.sol";
import {IFactory} from "./IFactory.sol";

interface ICore is IRegistry, IFactory {
    function dangerousMint(
        bytes calldata oid,
        uint256 amount,
        address[] calldata receivers
    ) external returns (uint256);

    function getOptionBalances(bytes calldata oid, address account)
        external
        view
        returns (uint256[] calldata);
}
