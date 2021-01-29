// SPDX-License-Identifier: MIT
pragma solidity >=0.6.2;

/**
 * @title   The Primitive House -> Manages collateral, leverages liquidity.
 * @author  Primitive
 */

// Open Zeppelin
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {
    ReentrancyGuard
} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
/* import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol"; */

// Primitive
import {
    IOption
} from "@primitivefi/contracts/contracts/option/interfaces/IOption.sol";

// Internal
import {Accelerator} from "./Accelerator.sol";
import {ICapitol} from "./interfaces/ICapitol.sol";
import {IERC20} from "./interfaces/IERC20.sol";
import {IHouse} from "./interfaces/IHouse.sol";
import {IVERC20} from "./interfaces/IVERC20.sol";
import {IWETH} from "./interfaces/IWETH.sol";
import {RouterLib} from "./libraries/RouterLib.sol";
import {SafeMath} from "./libraries/SafeMath.sol";
import {VirtualRouter} from "./VirtualRouter.sol";

import "hardhat/console.sol";

contract House is Ownable, VirtualRouter, Accelerator {
    /* using SafeERC20 for IERC20; */
    using SafeMath for uint256;

    event Executed(address indexed from, address indexed venue);
    // liquidity
    event Leveraged(
        address indexed depositor,
        address indexed optionAddress,
        address indexed pool,
        uint256 quantity
    );
    event Deleveraged(
        address indexed from,
        address indexed optionAddress,
        uint256 liquidity
    );

    event CollateralDeposited(
        address indexed depositor,
        address[] indexed tokens,
        uint256[] amounts
    );
    event CollateralWithdrawn(
        address indexed depositor,
        address[] indexed tokens,
        uint256[] amounts
    );

    // User position data structure
    // 1. Depositor address
    // 2. The underlying asset address
    // 3. The collateral asset address
    // 4. The representational debt unit balance
    struct Account {
        address depositor;
        address underlying;
        address collateral;
        mapping(address => uint256) balance;
    }

    // System balance sheet and collateral data structure
    // This data structure needs to carry a few items:
    // 1. If this reserve[asset] is enabled/exists
    // 2. The address for the ctoken to lend "foam" to.
    // 3. The nonce of the reserve for the allReserves array.
    // 4. The total quantity of reserve assets held by this contract
    // 5. The total debt of the system
    // 6. The total supply of representational debt units
    struct Reserve {
        bool enabled;
        address cTokenAddress;
        uint8 nonce;
        uint256 balance;
        uint256 totalDebt;
        uint256 totalSupplyOfDebt;
    }

    ICapitol public capitol;
    Accelerator public accelerator;

    bool public EXECUTING;
    uint256 public NONCE;
    address public CALLER;

    address[] public allReserves;
    uint256 public accountNonce;
    mapping(uint256 => Account) public accounts;

    mapping(address => mapping(address => uint256)) public debit;
    mapping(address => mapping(address => uint256)) public credit;

    modifier isEndorsed(address venue_) {
        require(capitol.getIsEndorsed(venue_), "House: NOT_ENDORSED");
        _;
    }

    constructor(
        address weth_,
        address registry_,
        address capitol_
    ) public VirtualRouter(weth_, registry_) {
        capitol = ICapitol(capitol_);
        accelerator = new Accelerator();
    }

    // ==== Balance Sheet Accounting ====

    function addTokens(
        address depositor,
        address[] memory tokens,
        uint256[] memory amounts
    ) public returns (bool) {
        uint256 tokensLength = tokens.length;
        for (uint256 i = 0; i < tokensLength; i++) {
            // Pull tokens from depositor.
            address asset = tokens[i];
            uint256 quantity = amounts[i];
            console.log("transferFrom venue to house", quantity);
            IERC20(asset).transferFrom(msg.sender, address(this), quantity);
        }
        console.log("internal add tokens to house");
        return _addTokens(depositor, tokens, amounts, false);
    }

    function _addTokens(
        address depositor,
        address[] memory tokens,
        uint256[] memory amounts,
        bool isDebit
    ) internal returns (bool) {
        uint256 tokensLength = tokens.length;
        uint256 amountsLength = amounts.length;
        require(tokensLength == amountsLength, "House: PARAMETER_LENGTH");
        for (uint256 i = 0; i < tokensLength; i++) {
            // Add liquidity to a depositor's respective pool balance.
            address asset = tokens[i];
            uint256 quantity = amounts[i];
            if (isDebit) {
                debit[asset][depositor] = debit[asset][depositor].add(quantity);
            } else {
                console.log(quantity);
                credit[asset][depositor] = credit[asset][depositor].add(
                    quantity
                );
            }
        }
        console.log(depositor);
        emit CollateralDeposited(depositor, tokens, amounts);
        return true;
    }

    function takeTokensFromUser(address token, uint256 quantity) external {
        address depositor = CALLER; //fix
        IERC20(token).transferFrom(depositor, msg.sender, quantity);
    }

    function removeTokens(
        address withdrawee,
        address[] memory tokens,
        uint256[] memory amounts
    ) public returns (bool) {
        // Remove balances from state.
        console.log("calling remove tokens");
        _removeTokens(CALLER, tokens, amounts, false);
        uint256 tokensLength = tokens.length;
        for (uint256 i = 0; i < tokensLength; i++) {
            // Push tokens to withdrawee.
            address asset = tokens[i];
            uint256 quantity = amounts[i];
            console.log("transferring tokens to withdrawee");
            IERC20(asset).transfer(withdrawee, quantity);
        }
        return true;
    }

    function _removeTokens(
        address withdrawee,
        address[] memory tokens,
        uint256[] memory amounts,
        bool isDebit
    ) internal returns (bool) {
        uint256 tokensLength = tokens.length;
        uint256 amountsLength = amounts.length;
        require(tokensLength == amountsLength, "House: PARAMETER_LENGTH");
        for (uint256 i = 0; i < tokensLength; i++) {
            // Remove liquidity to a withdrawee's respective pool balance.
            address asset = tokens[i];
            uint256 quantity = amounts[i];
            if (isDebit) {
                debit[asset][withdrawee] = debit[asset][withdrawee].sub(
                    quantity
                );
            } else {
                credit[asset][withdrawee] = credit[asset][withdrawee].sub(
                    quantity
                );
            }
        }
        emit CollateralWithdrawn(withdrawee, tokens, amounts);
        return true;
    }

    function creditBalanceOf(address depositor, address token)
        public
        view
        returns (uint256)
    {
        return credit[token][depositor];
    }

    function debitBalanceOf(address depositor, address token)
        public
        view
        returns (uint256)
    {
        return debit[token][depositor];
    }

    // ==== Options Management ====

    /**
     * @dev Mints virtual options to the receiver addresses.
     */
    function mintVirtualOptions(
        address optionAddress,
        uint256 quantity,
        address longReceiver,
        address shortReceiver
    ) public isEndorsed(msg.sender) {
        address receiver =
            longReceiver == shortReceiver ? longReceiver : address(this);
        address virtualOption = _virtualMint(optionAddress, quantity, receiver);
        if (receiver == address(this)) {
            IERC20(virtualOption).transfer(longReceiver, quantity);
            uint256 shortQuantity =
                RouterLib.getProportionalShortOptions(
                    IOption(virtualOption),
                    quantity
                );
            IERC20(IOption(virtualOption).redeemToken()).transfer(
                shortReceiver,
                shortQuantity
            );
        }
    }

    /**
     * @dev Pulls short and long options from `msg.sender` and burns them.
     */
    function burnVirtualOptions(
        address optionAddress,
        uint256 quantity,
        address receiver
    ) public isEndorsed(msg.sender) {
        address virtualOption = _virtualBurn(optionAddress, quantity, receiver);
    }

    // ==== Execution ====

    // Calls the accelerator intermediary to execute a transaction with a venue on behalf of caller.
    function execute(address venue, bytes calldata params)
        external
        payable
        nonReentrant
        returns (bool)
    {
        CALLER = msg.sender;
        accelerator.executeCall(venue, params);
        emit Executed(msg.sender, venue);
        return true;
    }
}
