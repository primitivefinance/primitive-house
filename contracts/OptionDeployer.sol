pragma solidity ^0.7.1;

/**
 * @title   The low-level contract for deploying option clones.
 * @notice  Warning: This contract should be inherited by a higher-level contract.
 * @author  Primitive
 */

import {PrimitiveERC20} from "./PrimitiveERC20.sol";
import {IPrimitiveERC20, IERC20} from "./interfaces/IPrimitiveERC20.sol";
import {IOptionDeployer} from "./interfaces/IOptionDeployer.sol";
import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";

contract OptionDeployer is IOptionDeployer {
    using SafeMath for uint256;

    address private immutable _template;
    // solhint-disable-next-line max-line-length
    bytes32 private constant _OPTION_SALT =
        0x56f3a99c8e36689645460020839ea1340cbbb2e507b7effe3f180a89db85dd87; // keccak("primitive-option")

    constructor() {
        bytes memory creationCode = type(PrimitiveERC20).creationCode;
        address template = Create2.deploy(0, _OPTION_SALT, creationCode);
        _template = template;
        IPrimitiveERC20(template).initialize(
            "Primitive Option Clone",
            "prmClone"
        );
    }

    function deployClone(string memory name, string memory symbol)
        public
        override
        returns (address)
    {
        // Calculates the salt for create2.
        bytes32 salt =
            keccak256(
                abi.encodePacked(
                    _OPTION_SALT
                    // additional params
                )
            );
        address instance = Clones.cloneDeterministic(_template, salt);
        IPrimitiveERC20(instance).initialize(name, symbol);
        return instance;
    }

    // ===== View =====
    function getTemplate() public view override returns (address) {
        return _template;
    }
}
