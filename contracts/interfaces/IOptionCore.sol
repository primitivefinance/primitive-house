pragma solidity ^0.7.1;
pragma experimental ABIEncoderV2;

import {IOptionData} from "./IOptionData.sol";
import {IOptionDeployer} from "./IOptionDeployer.sol";

interface IOptionCore is IOptionData, IOptionDeployer {
    function dangerousMint(
        bytes calldata oid,
        uint256 amount,
        address[] calldata receivers
    ) external returns (bool, uint256);

    function dangerousBurn(
        bytes calldata oid,
        uint256[] calldata amounts,
        address[] calldata accounts
    ) external returns (bool);

    function dangerousLongBurn(
        bytes calldata oid,
        uint256 amount,
        address account
    ) external returns (bool);

    function dangerousShortBurn(
        bytes calldata oid,
        uint256 amount,
        address account
    ) external returns (bool);
}
