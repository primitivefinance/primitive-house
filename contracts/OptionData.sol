pragma solidity ^0.7.1;

/**
 * @title   The low-level contract for storing option data.
 * @notice  Warning: This contract should be inherited by a higher-level contract.
 * @author  Primitive
 */

import {OptionDeployer} from "./OptionDeployer.sol";
import {IPrimitiveERC20, IERC20} from "./interfaces/IPrimitiveERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";

contract OptionData is OptionDeployer {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    string public constant NAME = "Primitive Option";
    uint8 public constant CALL = uint8(1);
    uint8 public constant PUT = uint8(2);

    struct TokenData {
        address longToken;
        address shortToken;
    }

    struct Parameters {
        address baseToken;
        address quoteToken;
        uint256 strikePrice;
        uint8 expiry;
        uint8 optionType;
    }

    event DeployedOptionClone(address indexed from, bytes indexed id);

    mapping(bytes => TokenData) internal _tokenData;
    mapping(bytes => Parameters) internal _parameters;
    bytes[] public allOptionIds;

    constructor() {}

    // ===== Option Management =====

    function createOption(
        address baseToken,
        address quoteToken,
        uint256 strikePrice,
        uint8 expiry,
        bool isCall
    )
        public
        returns (
            bytes memory,
            address,
            address
        )
    {
        // Symbol = 'long/short' + 'call/put' + baseTokenSymbol
        (uint8 optionType, string memory optionStringType) =
            generateType(isCall);
        string memory baseSymbol = IPrimitiveERC20(baseToken).symbol();
        string memory optionSymbol =
            string(abi.encodePacked(optionStringType, baseSymbol));
        string memory shortOptionSymbol =
            string(abi.encodePacked("s", optionStringType, baseSymbol));
        // Deploy erc-20 clones
        address longToken = deployClone(NAME, optionSymbol);
        address shortToken = deployClone(NAME, shortOptionSymbol);
        // Option ID
        bytes memory oid =
            abi.encodePacked(
                baseToken,
                quoteToken,
                strikePrice,
                expiry,
                optionType
            );
        // Option data storage
        TokenData storage optionData = _tokenData[oid];
        optionData.longToken = longToken;
        optionData.shortToken = shortToken;

        Parameters storage optionParameters = _parameters[oid];
        optionParameters.baseToken = baseToken;
        optionParameters.quoteToken = quoteToken;
        optionParameters.strikePrice = strikePrice;
        optionParameters.expiry = expiry;
        optionParameters.optionType = optionType;

        allOptionIds.push(oid);
        emit DeployedOptionClone(msg.sender, oid);
        return (oid, longToken, shortToken);
    }

    // ===== View =====
    function getTokenData(bytes memory id)
        public
        view
        returns (address, address)
    {
        TokenData memory data = _tokenData[id];
        return (data.longToken, data.shortToken);
    }

    function getParameters(bytes memory id)
        public
        view
        returns (
            address,
            address,
            uint256,
            uint8,
            uint8
        )
    {
        Parameters memory params = _parameters[id];
        return (
            params.baseToken,
            params.quoteToken,
            params.strikePrice,
            params.expiry,
            params.optionType
        );
    }

    // ===== Pure =====
    function generateType(bool isCall)
        public
        pure
        returns (uint8, string memory)
    {
        uint8 optionType;
        string memory optionStringType;
        if (isCall) {
            optionType = CALL;
            optionStringType = "call";
        } else {
            optionType = PUT;
            optionStringType = "put";
        }
        return (optionType, optionStringType);
    }
}
