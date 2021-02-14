pragma solidity ^0.7.1;

/**
 * @title   The low-level contract for storing option data.
 * @notice  Warning: This contract should be inherited by a higher-level contract.
 * @author  Primitive
 */

import {Factory} from "./Factory.sol";
import {IPrimitiveERC20, IERC20} from "./interfaces/IPrimitiveERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";

import {IRegistry} from "./interfaces/IRegistry.sol";

contract Registry is IRegistry, Factory {
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
        uint32 expiry;
        uint8 optionType;
    }

    event DeployedOptionClone(address indexed from, bytes32 indexed oid);

    mapping(bytes32 => TokenData) internal _tokenData;
    mapping(bytes32 => Parameters) internal _parameters;
    bytes32[] public allOptionIds;

    constructor() {}

    // ===== Option Management =====

    function createOption(
        address baseToken,
        address quoteToken,
        uint256 strikePrice,
        uint32 expiry,
        bool isCall
    )
        public
        override
        returns (
            bytes32,
            address,
            address
        )
    {
        // Symbol = 'long/short' + 'call/put' + baseTokenSymbol
        (uint8 optionType, string memory optionStringType) =
            generateType(isCall);

        // Deploy erc-20 clones
        address longToken =
            deployClone(
                NAME,
                string(
                    abi.encodePacked(
                        optionStringType,
                        IPrimitiveERC20(baseToken).symbol()
                    )
                )
            );
        address shortToken =
            deployClone(
                NAME,
                string(
                    abi.encodePacked(
                        "s",
                        optionStringType,
                        IPrimitiveERC20(baseToken).symbol()
                    )
                )
            );
        // Option ID
        bytes32 oid =
            keccak256(
                abi.encodePacked(
                    baseToken,
                    quoteToken,
                    strikePrice,
                    expiry,
                    optionType
                )
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
    function getTokenData(bytes32 oid)
        public
        view
        override
        returns (address, address)
    {
        TokenData memory data = _tokenData[oid];
        return (data.longToken, data.shortToken);
    }

    function getOIdFromParameters(
        address baseToken,
        address quoteToken,
        uint256 strikePrice,
        uint32 expiry,
        bool isCall
    ) public pure override returns (bytes32) {
        (uint8 optionType, ) = generateType(isCall);
        bytes32 oid =
            keccak256(
                abi.encodePacked(
                    baseToken,
                    quoteToken,
                    strikePrice,
                    expiry,
                    optionType
                )
            );
        return oid;
    }

    function getParameters(bytes32 oid)
        public
        view
        override
        returns (
            address,
            address,
            uint256,
            uint32,
            uint8
        )
    {
        Parameters memory params = _parameters[oid];
        return (
            params.baseToken,
            params.quoteToken,
            params.strikePrice,
            params.expiry,
            params.optionType
        );
    }

    function getAllOptionIdsLength() public view returns (uint256) {
        return allOptionIds.length;
    }

    // ===== Pure =====
    function generateType(bool isCall)
        public
        pure
        override
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
