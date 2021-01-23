pragma solidity >=0.6.2;

/**
 * @title Primitive Accelerator -> Leverage booster using internal capital system: Energy.
 */

import {IEnergy} from "../interfaces/IEnergy.sol";

contract Accelerator {
    IEnergy public energy;
    mapping(address => mapping(address => uint256)) public bank;

    // mutex
    bool private notEntered;

    modifier nonReentrant() {
        require(notEntered == false, "Energy: NON_REENTRANT");
        notEntered = true;
        _;
        notEntered = false;
    }

    /// @dev Checks the quantity of an operation to make sure its not zero. Fails early.
    modifier nonZero(uint256 quantity) {
        require(quantity > 0, "ERR_ZERO");
        _;
    }

    constructor(address energy_) public {
        energy = IEnergy(energy_);
    }

    function draw(address receiver, uint256 quantity) public returns (uint256) {
        return energy.draw(receiver, quantity);
    }
}
