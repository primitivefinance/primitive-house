pragma solidity >=0.5.12;

import {PrimitiveERC20} from "../PrimitiveERC20.sol";

contract TestERC20 is PrimitiveERC20 {
    constructor(uint256 totalSupply) public {
        _mint(msg.sender, totalSupply);
    }

    function mint(address to, uint256 quantity) external returns (bool) {
        _mint(to, quantity);
        return true;
    }

    function burn(address to, uint256 quantity) external returns (bool) {
        _burn(to, quantity);
        return true;
    }
}
