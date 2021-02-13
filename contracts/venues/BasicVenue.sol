pragma solidity >=0.6.2;

// Open Zeppelin
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Primitive

// Internal
import {Venue} from "./Venue.sol";
import {IHouse} from "../interfaces/IHouse.sol";
import {IWETH} from "../interfaces/IWETH.sol";
import {SafeMath} from "../libraries/SafeMath.sol";

import "hardhat/console.sol";

contract BasicVenue is Venue {
    using SafeERC20 for IERC20; // Reverts when `transfer` or `transferFrom` erc20 calls don't return proper data
    using SafeMath for uint256; // Reverts on math underflows/overflows

    event Initialized(address indexed from); // Emmitted on deployment

    // ===== Constructor =====

    constructor(address weth_, address house_) public Venue(weth_, house_) {
        house = IHouse(house_);
        emit Initialized(msg.sender);
    }

    // ===== Mutable =====

    // ===== Test =====

    uint256 private _test;

    function getTest() public view returns (uint256) {
        return _test;
    }

    event SetTest(uint256 value);

    function setTest(uint256 value) public {
        _test = value;

        emit SetTest(value);
    }

    // ===== View =====
}
