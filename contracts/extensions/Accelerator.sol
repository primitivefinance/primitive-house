pragma solidity >=0.6.2;

/**
 * @title Primitive Accelerator -> Leverage booster using internal capital system: Energy.
 */

import {IEnergy} from "../interfaces/IEnergy.sol";

contract Accelerator {
    IEnergy public energy;
    mapping(address => mapping(address => uint256)) public bank;

    constructor(address energy_) public {
        energy = IEnergy(energy_);
    }

    function draw(address receiver, uint256 quantity) public returns (uint256) {
        return energy.draw(receiver, quantity);
    }
}
