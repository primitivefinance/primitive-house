pragma solidity >=0.5.12;

import {IVERC20} from "./interfaces/IVERC20.sol";
import {IHouse} from "./interfaces/IHouse.sol";
import {IPrimitiveERC20} from "./interfaces/IPrimitiveERC20.sol";
import {PrimitiveERC20} from "./PrimitiveERC20.sol";

contract VERC20 is PrimitiveERC20, IVERC20 {
    IHouse public house;

    string private _name;
    string private _symbol;

    function initialize(address asset, address houseAddress) public override {
        require(address(house) == address(0x0), "ERR_INTIIALIZED");
        house = IHouse(houseAddress);
        /* string memory assetName = IVERC20(asset).name();
        string memory assetSymbol = IVERC20(asset).symbol();
        _name = string(abi.encodePacked("Virtual Primitive", assetName));
        _symbol = string(abi.encodePacked("vp", assetSymbol)); */
    }

    modifier onlyHouse {
        require(msg.sender == address(house), "ERR_NOT_HOUSE");
        _;
    }

    function mint(address to, uint256 quantity)
        external
        override
        onlyHouse
        returns (bool)
    {
        _mint(to, quantity);
        return true;
    }

    function burn(address to, uint256 quantity)
        external
        override
        onlyHouse
        returns (bool)
    {
        _burn(to, quantity);
        return true;
    }
}
