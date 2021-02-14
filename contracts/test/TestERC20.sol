pragma solidity >=0.5.12;

import {PrimitiveERC20} from "../PrimitiveERC20.sol";

contract TestERC20 is PrimitiveERC20 {
    constructor(uint256 totalSupply, string memory name_) public {
        _mint(msg.sender, totalSupply);
        initialize(name_, name_);
    }

    function mint(address to, uint256 quantity)
        external
        override
        returns (bool)
    {
        _mint(to, quantity);
        return true;
    }

    function burn(address to, uint256 quantity)
        external
        override
        returns (bool)
    {
        _burn(to, quantity);
        return true;
    }
}
