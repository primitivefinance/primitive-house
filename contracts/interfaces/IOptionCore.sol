pragma solidity ^0.7.1;
pragma experimental ABIEncoderV2;

import {IOptionData} from "./IOptionData.sol";
import {IOptionDeployer} from "./IOptionDeployer.sol";

interface IOptionCore is IOptionData, IOptionDeployer {
    function dangerousMint(
        bytes calldata oid,
        uint256 amount,
        address[] calldata receivers
    ) external returns (uint256);

    function dangerousExercise(
        bytes calldata oid,
        uint256 amount,
        uint256[] calldata claimAmounts,
        address burnedFrom
    ) external returns (uint256[] calldata);

    function dangerousSettle(
        bytes calldata oid,
        uint256 amount,
        uint256[] calldata claimAmounts,
        address burnFrom
    ) external returns (uint256[] calldata);

    function dangerousClose(
        bytes calldata oid,
        uint256[] calldata amounts,
        uint256[] calldata claimAmounts,
        address[] calldata accounts
    ) external returns (uint256[] calldata);

    function getOptionBalances(bytes calldata oid, address account)
        external
        view
        returns (uint256[] calldata);
}
