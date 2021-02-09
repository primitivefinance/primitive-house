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
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

// Primitive
import {IOptionCore} from "./interfaces/IOptionCore.sol";

// Internal
import {Accelerator} from "./Accelerator.sol";
import {ICapitol} from "./interfaces/ICapitol.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IHouse} from "./interfaces/IHouse.sol";
import {IWETH} from "./interfaces/IWETH.sol";
import {SafeMath} from "./libraries/SafeMath.sol";

import {Manager} from "./Manager.sol";

import "hardhat/console.sol";

contract House is Manager, Ownable, Accelerator, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    event Executed(address indexed from, address indexed venue);
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
        uint256 underlyingDebt;
        mapping(address => uint256) balance;
    }

    ICapitol public capitol;
    IOptionCore public core;
    Accelerator public accelerator;

    bool private _EXECUTING;
    uint256 private constant _NO_NONCE = uint256(-1);
    address private constant _NO_ADDRESS = address(21);

    uint256 private _NONCE;
    address private _CALLER;

    address[] private allReserves;
    uint256 private _accountNonce;

    mapping(uint256 => Account) public accounts;
    mapping(address => mapping(address => uint256)) private _balance;

    modifier isEndorsed(address venue_) {
        require(capitol.getIsEndorsed(venue_), "House: NOT_ENDORSED");
        _;
    }

    modifier isExec() {
        require(_NONCE != _NO_NONCE, "House: NO_NONCE");
        require(_CALLER != _NO_ADDRESS, "House: NO_ADDRESS");
        require(!_EXECUTING, "House: IN_EXECUTION");
        _EXECUTING = true;
        _;
        _EXECUTING = false;
    }

    constructor(address capitol_, address optionCore_) public {
        capitol = ICapitol(capitol_);
        core = IOptionCore(optionCore_);
        accelerator = new Accelerator();
    }

    // ==== Balance Sheet Accounting ====

    function addTokens(
        uint256 accountNonce,
        address depositor,
        address[] memory tokens,
        uint256[] memory amounts
    ) public returns (bool) {
        Account storage acc = accounts[accountNonce];
        uint256 tokensLength = tokens.length;
        _addTokens(depositor, tokens, amounts, false);
        for (uint256 i = 0; i < tokensLength; i++) {
            // Pull tokens from depositor.
            address asset = tokens[i];
            uint256 quantity = amounts[i];
            console.log("transferFrom venue to house", quantity);
            IERC20(asset).transferFrom(msg.sender, address(this), quantity);
        }
        console.log("internal add tokens to house");
        return true;
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
            balance[depositor][asset] = balance[depositor][asset].add(quantity);
        }
        console.log(depositor);
        emit CollateralDeposited(depositor, tokens, amounts);
        return true;
    }

    function addToken(address token, uint256 amount)
        public
        isExec
        returns (bool)
    {
        // Pull the tokens
        IERC20(token).transferFrom(msg.sender, address(this), amount);
        // Add the tokens to the executing position state
        return _addToken(token, amount);
    }

    function _addToken(address token, uint256 amount) internal returns (bool) {
        Account storage acc = accounts[getExecutingNonce()];
        acc.balance[token] = acc.balance[token].add(quantity);
        emit CollateralDeposited(acc.depositor, token, amount);
        return true;
    }

    function removeToken(address token, uint256 amount)
        public
        isExec
        returns (bool)
    {
        // Remove tokens from account state
        _removeToken(token, amount);
        // Push the tokens to the msg.sender.
        return IERC20(token).transfer(msg.sender, amount);
    }

    function _removeToken(address token, uint256 amount)
        internal
        returns (bool)
    {
        Account storage acc = accounts[getExecutingNonce()];
        acc.balance[token] = acc.balance[token].sub(amount);
        emit CollateralWithdrawn(acc.depositor, token, amount);
        return true;
    }

    function takeTokensFromUser(address token, uint256 quantity) external {
        IERC20(token).transferFrom(_CALLER, msg.sender, quantity);
    }

    function removeTokens(
        address withdrawee,
        address[] memory tokens,
        uint256[] memory amounts
    ) public returns (bool) {
        // Remove balances from state.
        console.log("calling remove tokens");
        _removeTokens(_CALLER, tokens, amounts, false);
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
            balance[withdrawee][asset] = balance[withdrawee][asset].sub(
                quantity
            );
        }
        emit CollateralWithdrawn(withdrawee, tokens, amounts);
        return true;
    }

    // ==== Options Management ====

    /**
     * @dev Mints virtual options to the receiver addresses.
     */
    function mintOptions(
        bytes memory oid,
        uint256 quantity,
        address[] memory receivers
    ) public isEndorsed(msg.sender) isExec returns (uint256) {
        // Get the account that is being updated
        Account storage acc = accounts[getExecutingNonce()];
        // Update the underlying debt to add minted option quantity
        uint256 prevDebt = acc.underlyingDebt;
        acc.underlyingDebt = prevDebt.add(quantity);
        uint256 successCode = core.dangerousMint(oid, receivers);
        return successCode;
    }

    /**
     * @dev Pulls short and long options from `msg.sender` and burns them.
     */
    function burnOptions(
        bytes memory oid,
        uint256 quantity,
        address[] memory holders
    ) public isEndorsed(msg.sender) isExec returns (uint256) {
        // Get the account that is being updated
        Account storage acc = accounts[getExecutingNonce()];
        // Update the underlying debt to subtract the option quantity
        acc.underlyingDebt = acc.underlyingDebt.sub(quantity);
        uint256 successCode = core.dangerousBurn(oid, holders);
        return successCode;
    }

    // ==== Execution ====

    // Calls the accelerator intermediary to execute a transaction with a venue on behalf of caller.
    function execute(
        uint256 accountNonce,
        address venue,
        bytes calldata params
    ) external payable nonReentrant returns (bool) {
        if (accountNonce == 0) {
            accountNonce = _accountNonce++;
            accounts[accountNonce].depositor = msg.sender;
        } else {
            require(
                accounts[accountNonce].depositor == msg.sender,
                "House: NOT_DEPOSITOR"
            );
            require(accountNonce < _accountNonce, "House: ABOVE_NONCE");
        }
        _CALLER = msg.sender;
        _NONCE = accountNonce;
        accelerator.executeCall(venue, params);
        _CALLER = _NO_ADDRESS;
        _NONCE = _NO_NONCE;
        emit Executed(msg.sender, venue);
        return true;
    }

    // ===== Invariant Rules =====

    function mintingInvariant()
        public
        override
        isExec
        returns (uint256, uint256)
    {
        // Get the account that is being updated
        Account storage acc = accounts[getExecutingNonce()];
        return (uint256(0), acc.underlyingDebt);
    }

    function burningInvariant()
        public
        override
        isExec
        returns (uint256, uint256)
    {
        // Get the account that is being updated
        Account storage acc = accounts[getExecutingNonce()];
        return (uint256(0), acc.underlyingDebt);
    }

    // ==== View ====

    function isExecuting() public view returns (bool) {
        return _EXECUTING;
    }

    function getExecutingNonce() public view returns (uint256) {
        return _NONCE;
    }

    function getExecutingCaller() public view returns (address) {
        return _CALLER;
    }

    function getAccountNonce() public view returns (uint256) {
        return _accountNonce;
    }

    function getReserves() public view returns (address[] memory) {
        return allReserves;
    }

    function getBalance(address account, address token)
        public
        view
        returns (uint256)
    {
        return _balance[account][token];
    }
}
