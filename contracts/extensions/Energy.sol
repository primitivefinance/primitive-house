pragma solidity >=0.6.2;

/**
 * @title Primitive Energy -> Capital storage for internal network use.
 */

import {IEnergy} from "../interfaces/IEnergy.sol";

contract Energy is IEnergy {
    constructor() public {}

    function erase(address receiver, uint256 amount)
        external
        override
        returns (uint256)
    {
        return 1;
    }

    function draw(address receiver, uint256 amount)
        external
        override
        returns (uint256)
    {
        return 1;
    }

    function debit() external view override returns (uint256) {
        return 1;
    }

    function credit() external view override returns (uint256) {
        return 1;
    }
}
