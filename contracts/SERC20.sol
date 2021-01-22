pragma solidity >=0.5.12 <=0.6.2;

import { ISERC20 } from "./interfaces/ISERC20.sol";
import { IHouse } from "./interfaces/IHouse.sol";
import {IPrimitiveERC20} from "./interfaces/IPrimitiveERC20.sol";
import {PrimitiveERC20} from "./PrimitiveERC20.sol";

contract SERC20 is PrimitiveERC20, ISERC20 {
    IHouse public house;

    string private _name;
    string private _symbol;
    uint256 public constant decimals = 18;

    function initialize(address asset, address houseAddress) public override {
        require(address(house) == address(0x0), "ERR_INTIIALIZED");
        house = IHouse(houseAddress);
        string memory assetName = ISERC20(asset).name();
        string memory assetSymbol = ISERC20(asset).symbol();
        _name = string(abi.encodePacked("Virtual Primitive", assetName));
        _symbol = string(abi.encodePacked("vp", assetSymbol));
    }

    function name() public override view returns (string memory) {
        return _name;
    }

    function symbol() public override view returns (string memory) {
        return _symbol;
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
