pragma solidity ^0.7.1;
pragma experimental ABIEncoderV2;

import {IRegistry} from "./IRegistry.sol";
import {IFactory} from "./IFactory.sol";

interface ICore is IRegistry, IFactory {
    function dangerousMint(
        bytes32 oid,
        uint256 amount,
        address[] calldata receivers
    ) external returns (uint256);

    function dangerousExercise(bytes32 oid, uint256 amount)
        external
        returns (uint256, uint256);

    function dangerousRedeem(
        bytes32 oid,
        uint256 inputShort,
        uint256 minOutputQuote,
        uint256 quoteBalance
    ) external returns (uint256);

    function dangerousClose(bytes32 oid, uint256 amount)
        external
        returns (uint256);

    function getOptionBalances(bytes32 oid, address account)
        external
        view
        returns (uint256[] calldata);
}
