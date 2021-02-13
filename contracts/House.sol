// SPDX-License-Identifier: MIT
pragma solidity >=0.6.2;

/**
 * @title   The Primitive House -> Manages collateral, leverages liquidity.
 * @author  Primitive
 */

// Open Zeppelin
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {
    ReentrancyGuard
} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

// Primitive
import {ICore} from "./interfaces/ICore.sol";
import {IFlash} from "./interfaces/IFlash.sol";

// Internal
import {Accelerator} from "./Accelerator.sol";
import {IHouse} from "./interfaces/IHouse.sol";
import {IWETH} from "./interfaces/IWETH.sol";
import {SafeMath} from "./libraries/SafeMath.sol";
import {Manager} from "./Manager.sol";

import "hardhat/console.sol";

contract House is Manager, Ownable, Accelerator, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    /**
     * @dev If (!_EXECUTING), `_NONCE` = `_NO_NONCE`.
     */
    uint256 private constant _NO_NONCE = uint256(-1);

    /**
     * @dev If (!_EXECUTING), `_ADDRESS` = `_NO_ADDRESS`.
     */
    address private constant _NO_ADDRESS = address(21);

    /**
     * @notice Event emitted after a successful `execute` call on the House.
     */
    event Executed(address indexed from, address indexed venue);

    /**
     * @notice Event emitted after a `dangerousMint` has succeeded.
     */
    event OptionsMinted(
        address indexed from,
        uint256 amount,
        address indexed longReceiver,
        address indexed shortReceiver
    );

    /**
     * @notice Event emitted after a `dangerousBurn` has succeeded.
     */
    event OptionsBurned(
        address indexed from,
        uint256 longAmount,
        uint256 shortAmount,
        address indexed longReceiver,
        address indexed shortReceiver
    );

    /**
     * @notice Event emitted after a `_universalDebt` balance has been updated.
     */
    event UpdatedUniversalDebt(
        uint256 indexed accountNonce,
        address indexed token,
        uint256 newBalance
    );

    /**
     * @notice Event emitted after a `_strikeClaim` balance has been updated.
     */
    event UpdatedQuoteClaim(
        uint256 indexed accountNonce,
        address indexed shortOption,
        address indexed token,
        uint256 newBalance
    );

    /**
     * @notice Event emitted when `token` is deposited to the House.
     */
    event CollateralDeposited(
        uint256 indexed nonce,
        address indexed token,
        uint256 indexed tokenId,
        uint256 amount
    );

    /**
     * @notice Event emitted when `token` is pushed to `msg.sender`, which should be `_VENUE`.
     */
    event CollateralWithdrawn(
        uint256 indexed nonce,
        address indexed token,
        uint256 indexed tokenId,
        uint256 amount
    );

    /**
     * @notice User account data structure.
     * 1. Depositor address
     * 2. The wrapped ERC1155 token
     * 3. The id for the wrapped token
     * 4. The balance of the wrapped token
     * 5. The debt of the underlying token
     * 6. The delta of debt in the executing block
     */
    struct Account {
        address depositor;
        address wrappedToken;
        uint256 wrappedId;
        uint256 balance;
        uint256 debt;
        uint256 delta;
    }

    /**
     * @dev The contract with core option logic.
     */
    ICore internal _core;

    /**
     * @dev The contract to execute transactions on behalf of the House.
     */
    Accelerator internal _accelerator;

    /**
     * @dev If the `execute` function was called this block.
     */
    bool private _EXECUTING;

    /**
     * @dev If _EXECUTING, the account with nonce is being manipulated
     */
    uint256 private _NONCE;

    /**
     * @dev If _EXECUTING, the `msg.sender` of `execute`.
     */
    address private _CALLER;

    /**
     * @dev If _EXECUTING, the venue being used to manipulate the account.
     */
    address private _VENUE;

    /**
     * @dev The current nonce that will be set when a new account is initialized.
     */
    uint256 private _accountNonce;

    /**
     * @dev All the accounts from a nonce of 0 to `_accountNonce` - 1.
     */
    mapping(uint256 => Account) private _accounts;

    /**
     * @dev The universal debt balance for each real token.
     *      _universalDebt[token] = amount.
     */
    mapping(address => uint256) internal _universalDebt;

    /**
     * @dev The amount of quote tokens that are claimable by short option tokens.
     */
    mapping(address => mapping(address => uint256)) internal _quoteClaim;

    modifier isEndorsed(address venue_) {
        //require(_capitol.getIsEndorsed(venue_), "House: NOT_ENDORSED");
        _;
    }

    /**
     * @notice  A mutex to use during an `execute` call.
     */
    modifier isExec() {
        require(_NONCE != _NO_NONCE, "House: NO_NONCE");
        require(_CALLER != _NO_ADDRESS, "House: NO_ADDRESS");
        require(_VENUE != msg.sender, "House: NO_VENUE");
        require(!_EXECUTING, "House: IN_EXECUTION");
        _EXECUTING = true;
        _;
        _EXECUTING = false;
    }

    constructor(address optionCore_) {
        _accelerator = new Accelerator();
        _core = ICore(optionCore_);
    }

    // ====== Transfers ======

    /**
     * @notice  Transfers ERC20 tokens from the executing account's depositor to the executing _VENUE.
     * @param   token The address of the ERC20.
     * @param   amount The amount of ERC20 to transfer.
     * @return  Whether or not the transfer succeeded.
     */
    function takeTokensFromUser(address token, uint256 amount)
        external
        isExec
        returns (bool)
    {
        IERC20(token).safeTransferFrom(
            _accounts[getExecutingNonce()].depositor,
            msg.sender,
            amount
        );
        return true;
    }

    /**
     * @notice  Transfer ERC1155 tokens from `msg.sender` to this contract.
     * @param   token The ERC1155 token to call.
     * @param   wid The ERC1155 token id to transfer.
     * @param   amount The amount of ERC1155 with `wid` to transfer.
     * @return  The actual amount of `token` sent in to this contract.
     */
    function _internalWrappedTransfer(
        address token,
        uint256 wid,
        uint256 amount
    ) internal returns (uint256) {
        uint256 prevBal = IERC1155(token).balanceOf(address(this), wid);
        IERC1155(token).safeTransferFrom(
            msg.sender,
            address(this),
            wid,
            amount,
            ""
        );
        uint256 postBal = IERC1155(token).balanceOf(address(this), wid);
        return postBal.sub(prevBal);
    }

    /**
     * @notice  Transfer ERC20 tokens from `msg.sender` to this contract.
     * @param   token The address of the ERC20 token.
     * @param   amount The amount of ERC20 tokens to transfer.
     * @return  The actual amount of `token` sent in to this contract.
     */
    function _internalTransfer(address token, uint256 amount)
        internal
        returns (uint256)
    {
        uint256 prevBal = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        uint256 postBal = IERC20(token).balanceOf(address(this));
        return postBal.sub(prevBal);
    }

    // ===== Collateral Management =====

    /**
     * @notice  Pulls collateral tokens from `msg.sender` which is the executing `_VENUE`.
     *          Adds the amount of pulled tokens to the Account with `_NONCE`.
     * @dev     Reverts if no wrapped tokens are actually sent to this contract.
     * @param   wrappedToken The ERC1155 token contract to call to.
     * @param   wrappedId The ERC1155 token id to transfer from `msg.sender` to this contract.
     * @param   amount The amount of ERC1155 tokens to transfer.
     * @return  Whether or not the transfer succeeded.
     */
    function addCollateral(
        address wrappedToken,
        uint256 wrappedId,
        uint256 amount
    ) public isExec returns (uint256) {
        return _addCollateral(wrappedToken, wrappedId, amount);
    }

    function _addCollateral(
        address token,
        uint256 wid,
        uint256 amount
    ) internal returns (uint256) {
        Account storage acc = _accounts[getExecutingNonce()];
        if (acc.wrappedToken != token || acc.wrappedId != wid) {
            _initializeCollateral(acc, token, wid);
        }
        // Pull the tokens
        uint256 actualAmount = _internalWrappedTransfer(token, wid, amount);
        require(actualAmount > 0, "House: ADD_ZERO");
        // Add the tokens to the executing account state
        acc.balance = acc.balance.add(amount);
        emit CollateralDeposited(_NONCE, token, wid, amount);
        return actualAmount;
    }

    /**
     * @notice  Called to update an Account with `_NONCE` with a `token` and `wid`.
     * @param   acc The Account to manipulate, fetched with the executing `_NONCE`.
     * @param   token The wrapped ERC1155 contract.
     * @param   wid The wrapped ERC1155 token id.
     * @return  Whether or not the intiialization succeeded.
     */
    function _initializeCollateral(
        Account storage acc,
        address token,
        uint256 wid
    ) internal returns (bool) {
        require(acc.balance == uint256(0), "House: INITIALIZED");
        acc.wrappedToken = token;
        acc.wrappedId = wid;
        return true;
    }

    /**
     * @notice  Transfers `wrappedToken` with `wrappedId` from this contract to the `msg.sender`.
     * @dev     The `msg.sender` should always be the `_VENUE`, since this can only be called `inExec`.
     * @param   wrappedToken The ERC1155 token contract to call to.
     * @param   wrappedId The ERC1155 token id to transfer from `msg.sender` to this contract.
     * @param   amount The amount of ERC1155 tokens to transfer.
     * @return  Whether or not the transfer succeeded.
     */
    function removeCollateral(
        address wrappedToken,
        uint256 wrappedId,
        uint256 amount
    ) public isExec returns (bool) {
        // Remove wrappedTokens from account state
        bool success = _removeCollateral(wrappedToken, wrappedId, amount);
        // Push the wrappedTokens to the msg.sender.
        IERC1155(wrappedToken).safeTransferFrom(
            address(this),
            msg.sender,
            wrappedId,
            amount,
            ""
        );
        emit CollateralWithdrawn(_NONCE, wrappedToken, wrappedId, amount);
        return success;
    }

    function _removeCollateral(
        address token,
        uint256 wip,
        uint256 amount
    ) internal returns (bool) {
        Account storage acc = _accounts[getExecutingNonce()];
        require(acc.wrappedId == wip, "House: INVALID_ID");
        require(acc.wrappedToken == token, "House: INVALID_TOKEN");
        uint256 balance = acc.balance;
        if (amount == uint256(-1)) {
            amount = balance;
        }
        acc.balance = acc.balance.sub(amount);
        return true;
    }

    // ===== Internal Balances =====

    function _internalUpdate(address token, uint256 newBalance)
        internal
        isExec
    {
        _universalDebt[token] = newBalance;
        emit UpdatedUniversalDebt(_NONCE, token, newBalance);
    }

    function _quoteClaimUpdate(
        address shortOption,
        address token,
        uint256 newBalance
    ) internal isExec {
        _quoteClaim[shortOption][token] = newBalance;
        emit UpdatedQuoteClaim(_NONCE, shortOption, token, newBalance);
    }

    function _addAccountDebt(uint256 amount) internal isExec returns (bool) {
        Account storage acc = _accounts[getExecutingNonce()];
        acc.debt = acc.debt.add(amount);
        return true;
    }

    function _subtractAccountDebt(uint256 amount)
        internal
        isExec
        returns (bool)
    {
        Account storage acc = _accounts[getExecutingNonce()];
        acc.debt = acc.debt.sub(amount);
        return true;
    }

    // ===== Option Core =====

    /**
     * @notice  Mints options to the receiver addresses.
     * @param   oid The option data id used to fetch option related data.
     * @param   requestAmt The requestAmt of options requested to be minted.
     * @param   receivers The long option ERC20 receiver, and short option ERC20 receiver.
     * @return  Whether or not the mint succeeded.
     */
    function mintOptions(
        bytes memory oid,
        uint256 requestAmt,
        address[] memory receivers
    ) public isEndorsed(msg.sender) isExec returns (bool) {
        // Execute the mint
        _core.dangerousMint(oid, requestAmt, receivers); // calls mintingInvariant()

        // Update internal base token balance
        (address baseToken, , , , ) = _core.getParameters(oid);
        uint256 newBalance = _universalDebt[baseToken].add(requestAmt);
        _internalUpdate(baseToken, newBalance);
        return true;
    }

    /**
     * @notice  Mints options to the receiver addresses without checking collateral.
     * @param   oid The option data id used to fetch option related data.
     * @param   requestAmt The requestAmt of long and short option ERC20 tokens to mint.
     * @param   receivers The long option ERC20 receiver, and short option ERC20 receiver.
     * @return  Whether or not the mint succeeded.
     */
    function borrowOptions(
        bytes memory oid,
        uint256 requestAmt,
        address[] memory receivers
    ) public isEndorsed(msg.sender) isExec returns (uint256) {
        // Get the account that is being updated
        Account storage acc = _accounts[getExecutingNonce()];
        // Update the acc delta
        acc.delta = requestAmt;
        // Update acc debt balance
        acc.balance = acc.balance.add(requestAmt);
        uint256 actualAmt = _core.dangerousMint(oid, requestAmt, receivers);
        // Reset delta by subtracting from actual amount borrowed
        acc.delta = actualAmt.sub(acc.delta);
        return actualAmt;
    }

    // ===== Execution =====

    /**
     * @notice  Manipulates an Account with `accountNonce` using a venue.
     * @dev     Warning: low-level call is executed by `_accelerator` contract.
     * @param   accountNonce The Account to manipulate.
     * @param   venue The Venue to call and execute `params`.
     * @param   params The encoded selector and arguments for the `_accelerator` to call `venue` with.
     * @return  Whether the execution succeeded or not.
     */
    function execute(
        uint256 accountNonce,
        address venue,
        bytes calldata params
    ) external payable nonReentrant returns (bool) {
        if (accountNonce == 0) {
            accountNonce = _accountNonce++;
            _accounts[accountNonce].depositor = msg.sender;
        } else {
            require(
                _accounts[accountNonce].depositor == msg.sender,
                "House: NOT_DEPOSITOR"
            );
            require(accountNonce < _accountNonce, "House: ABOVE_NONCE");
        }
        _CALLER = msg.sender;
        _NONCE = accountNonce;
        _accelerator.executeCall(venue, params);
        _CALLER = _NO_ADDRESS;
        _NONCE = _NO_NONCE;
        emit Executed(msg.sender, venue);
        return true;
    }

    // ====== Invariant Rules ======

    // ===== View =====

    function isExecuting() public view returns (bool) {
        return _EXECUTING;
    }

    function getExecutingNonce() public view returns (uint256) {
        return _NONCE;
    }

    function getExecutingCaller() public view returns (address) {
        return _CALLER;
    }

    function getExecutingVenue() public view returns (address) {
        return _VENUE;
    }

    function getAccountNonce() public view returns (uint256) {
        return _accountNonce;
    }

    function getAccount(uint256 accountNonce)
        public
        view
        returns (
            address,
            address,
            uint256,
            uint256
        )
    {
        Account memory acc = _accounts[accountNonce];
        return (acc.depositor, acc.wrappedToken, acc.wrappedId, acc.balance);
    }

    function getCore() public view returns (address) {
        return address(_core);
    }

    function getAccelerator() public view returns (address) {
        return address(_accelerator);
    }
}
