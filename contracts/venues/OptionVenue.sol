pragma solidity ^0.7.1;

/**
 * @title A simple venue implementation that handles option Accounts for the House.sol contract.
 */

// Open Zeppelin
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

// Internal
import {Venue} from "./Venue.sol";
import {SafeMath} from "../libraries/SafeMath.sol";

import "hardhat/console.sol";

contract OptionVenue is Venue {
    using SafeERC20 for IERC20; // Reverts when `transfer` or `transferFrom` erc20 calls don't return proper data
    using SafeMath for uint256; // Reverts on math underflows/overflows

    event Initialized(address indexed from); // Emmitted on deployment

    // ===== Constructor =====

    constructor(
        address weth_,
        address house_,
        address wToken_
    ) Venue(weth_, house_, wToken_) {
        emit Initialized(msg.sender);
    }

    // ===== Mutable =====

    struct Leg {
        PositionType posType;
        bytes32 oid;
        uint256 amount;
    }

    struct LongShort {
        Leg longLeg;
        Leg shortLeg;
        uint256 maxUnder;
        uint256 maxStable;
    }

    struct MultiLeg {
        Leg[] legs;
        uint8 legLength;
        uint8 currSum;
    }

    uint8 public constant MAX_LEGS_LENGTH = uint8(4);

    mapping(uint256 => MultiLeg) public positions;

    address public _NO_ADDRESS = address(0x0);

    enum PositionType {LONG_CALL, SHORT_CALL, LONG_PUT, SHORT_PUT}

    /* function addOptionLeg(
        uint256 positionNonce,
        bytes32 oid,
        uint256 amount,
        bool longDirection
    ) public {
        (, , uint256 strikePrice, uint32 expiry, uint8 optionType) =
            _house.getParameters(oid);
        (address long, address short) = _house.getOptionTokens(oid);
        // Get the type of option
        PositionType posType =
            longDirection
                ? optionType == uint8(1)
                    ? PositionType.LONG_CALL
                    : PositionType.LONG_PUT
                : optionType == uint8(1)
                ? PositionType.SHORT_CALL
                : PositionType.SHORT_PUT;

        // Get the storage and memory objs
        MultiLeg storage pos = positions[positionNonce];
        Leg memory leg;
        uint8 len = pos.legLength;
        uint8 sum = pos.currSum;
        if (len > 0) {
            leg = pos.legs[len - 1];
            sum += uint8(leg.posType);
        }

        // lets just assume len is up to 2
        if (sum == uint8(0)) {
            // Long call
        } else if (sum == uint8(1)) {
            // Call spread
        } else if (sum == uint8(2)) {
            // Short call or straddle
        } else if (sum == uint8(3)) {
            // RR or Synthetic Long
        } else if (sum == uint8(4)) {
            // Long Put or Short Straddle
        } else if (sum == uint8(5)) {
            // Put Spread
        } else if (sum == uint8(6)) {
            // Short Put
        }

        Leg memory newLeg;
        newLeg.posType = posType;
        newLeg.oid = oid;
        newLeg.amount = amount;
        uint8 product = uint8(ls.longLeg.posType) * uint8(posType);
        sum += uint8(posType);

        uint256 maxUnder;
        uint256 maxStable;
    } */

    enum LegPosition {FIRST_LEG, SECOND_LEG, THIRD_LEG, FOURTH_LEG}

    function batchMintThenCollateralize(
        bytes32[] memory oids,
        uint256[] memory amounts
    ) public {
        // mint options for each oid
        (address[] memory tokens, uint256[] memory newAmts) =
            batchMintOptions(oids, amounts);
        // call wrapTokenBatch to add a batch of tokens to the House as collateral
        _wrapTokenBatch(tokens, newAmts);
    }

    function batchMintOptions(bytes32[] memory oids, uint256[] memory amounts)
        public
        returns (address[] memory, uint256[] memory)
    {
        uint256 oidsLength = oids.length;
        uint256 amountsLength = amounts.length;
        require(oidsLength == amountsLength, "House: LENGTHS");
        // Receivers are this address
        address[] memory receivers = new address[](2);
        receivers[0] = address(this);
        receivers[1] = address(this);

        address[] memory tokens = new address[](oidsLength.mul(2));
        uint256[] memory newAmts = new uint256[](oidsLength.mul(2));
        uint256 index;
        for (uint256 i = 0; i < amountsLength; i++) {
            bytes32 oid = oids[i];
            uint256 amount = amounts[i];
            _mintOptions(oid, amount, receivers, false);
            (address long, address short) = _house.getOptionTokens(oid);
            tokens[index] = long;
            tokens[index + 1] = short;
            newAmts[index] = amount;
            newAmts[index + 1] = amount;
            index += 2;
        }
        return (tokens, newAmts);
    }

    // ===== View =====

    function calculateMaxLoss(
        PositionType posType,
        uint256 amount,
        uint256 strikePrice
    ) public pure returns (uint256, uint256) {
        uint256 maxUnderlyingLoss;
        uint256 maxStableLoss;
        if (
            posType == PositionType.LONG_CALL ||
            posType == PositionType.SHORT_CALL
        ) {
            maxUnderlyingLoss = amount;
        } else {
            maxStableLoss = amount.mul(strikePrice).div(1 ether);
        }

        return (maxUnderlyingLoss, maxStableLoss);
    }
}
