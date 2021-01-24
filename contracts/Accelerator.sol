pragma solidity >=0.6.2;

/**
 * @title Primitive Accelerator -> Execution contract between House and Venues.
 */

import {IEnergy} from "./interfaces/IEnergy.sol";

contract Accelerator {
    /* IEnergy public energy;
    mapping(address => mapping(address => uint256)) public bank;

    constructor(address energy_) public {
        energy = IEnergy(energy_);
    } */

    function executeCall(address target, bytes calldata params)
        external
        payable
    {
        (bool success, bytes memory returnData) =
            target.call{value: msg.value}(params);
        require(
            success &&
                (returnData.length == 0 || abi.decode(returnData, (bool))),
            "Accelerator: EXECUTION_FAIL"
        );
    }
}
