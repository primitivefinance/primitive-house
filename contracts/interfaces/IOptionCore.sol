pragma solidity ^0.7.1;
pragma experimental ABIEncoderV2;

import {IOptionData} from "./IOptionData.sol";
import {IOptionDeployer} from "./IOptionDeployer.sol";

interface IOptionCore is IOptionData, IOptionDeployer {
    function dangerousMint(
        bytes calldata oid,
        uint256 amount,
        address[] calldata receivers
    ) external returns (bool);

    function dangerousBurn(
        bytes calldata oid,
        uint256[] calldata amounts,
        address[] calldata accounts
    ) external returns (bool);
}
