// SPDX-License-Identifier: MIT
pragma solidity >=0.6.2;

/**
 * @title   The Primitive Virtualizer -> Issues virtual representations of assets and options.
 * @author  Primitive
 */

import {SafeMath} from "./libraries/SafeMath.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import {IPrimitiveERC20} from "./interfaces/IPrimitiveERC20.sol";
import {
    IOption
} from "@primitivefi/contracts/contracts/option/interfaces/IOption.sol";
import {ISERC20} from "./interfaces/ISERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract Virtualizer is Ownable {
    using SafeERC20 for IERC20;
    using SafeERC20 for IOption;
    using SafeMath for uint256;

    struct ReserveData {
        ISERC20 virtualToken;
    }

    IRegistry public registry;

    mapping(address => address) public virtualOptions;
    mapping(address => ReserveData) internal _reserves;

    // mutex
    bool private _notEntered;

    modifier nonReentrant() {
        require(notEntered == 1, "Virtualizer: NON_REENTRANT");
        notEntered = true;
        _;
        notEntered = false;
    }

    constructor(address registry_) public {
        registry = IRegistry(registry_);
    }

    // Initializes a new virtual asset.
    function issueVirtual(address asset, address virtualAsset) external {
        ISERC20(virtualAsset).initialize(asset, address(this));
        ReserveData storage reserve = _reserves[asset];
        reserve.virtualToken = ISERC20(virtualAsset);
    }

    // Initialize a virtual option.
    function deployVirtualOption(address optionAddress)
        public
        returns (address)
    {
        (
            address underlying,
            address strike,
            ,
            uint256 baseValue,
            uint256 quoteValue,
            uint256 expiry
        ) = IOption(optionAddress).getParameters();
        // fix - this doubles the gas cost, maybe just make them virtual?
        address virtualOption =
            registry.deployOption(
                address(_reserves[underlying].virtualToken),
                address(_reserves[strike].virtualToken),
                baseValue,
                quoteValue,
                expiry
            );

        virtualOptions[optionAddress] = virtualOption;
        return virtualOption;
    }
}
