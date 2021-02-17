// SPDX-License-Identifier: MIT
pragma solidity ^0.7.1;
pragma experimental ABIEncoderV2;

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
import {BasicERC1155Receiver} from "./utils/BasicERC1155Receiver.sol";

import "hardhat/console.sol";

contract House is Manager, Accelerator, ReentrancyGuard, BasicERC1155Receiver {
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
        uint256[] oids;
    }

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
    uint256 private _NONCE = _NO_NONCE;

    /**
     * @dev If _EXECUTING, the venue being used to manipulate the account.
     */
    address private _VENUE = _NO_ADDRESS;

    /**
     * @dev If _EXECUTING, the Account.depositor by default, _VENUE if set.
     */
    address private _EXECUTING_SENDER = _NO_ADDRESS;

    /**
     * @dev The current nonce that will be set when a new account is initialized.
     */
    uint256 private _accountNonce;

    /**
     * @dev All the accounts from a nonce of 0 to `_accountNonce` - 1.
     */
    mapping(uint256 => Account) private _accounts;

    /**
     * @dev The options -> token -> amount claim.
     */
    mapping(bytes32 => mapping(address => uint256)) internal _houseBalance;

    /**
     * @dev The token -> amount collateral locked amount.
     */
    mapping(address => uint256) internal _collateralBalance;

    /**
     * @notice  A mutex to use during an `execute` call.
     */
    modifier isExec() {
        require(_NONCE != _NO_NONCE, "House: NO_NONCE");
        require(_VENUE == msg.sender, "House: NO_VENUE");
        require(!_EXECUTING, "House: IN_EXECUTION");
        _EXECUTING = true;
        _;
        _EXECUTING = false;
    }

    constructor(address core_) Manager(core_) {
        _accelerator = new Accelerator();
    }

    // ====== Transfers ======

    /**
     * @notice  Transfers ERC20 tokens from the executing account's depositor to the executing _VENUE.
     * @param   token The address of the ERC20.
     * @param   amount The amount of ERC20 to transfer.
     * @return  Whether or not the transfer succeeded.
     */
    function takeTokensFromUser(address token, uint256 amount)
        public
        isExec
        returns (bool)
    {
        return _takeTokensFromUser(token, amount);
    }

    function _takeTokensFromUser(address token, uint256 amount)
        internal
        returns (bool)
    {
        IERC20(token).safeTransferFrom(
            _accounts[getExecutingNonce()].depositor, // Account owner
            msg.sender, // The venue
            amount
        );
        return true;
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
            console.log("initializing collateral");
            _initializeCollateral(acc, token, wid);
        }

        console.log("pull wrapped tokens");
        // Pull the tokens
        uint256 actualAmount = _pullWrappedToken(token, wid, amount);
        require(actualAmount > 0, "House: ADD_ZERO");
        console.log("add to account balance");
        // Add the tokens to the executing account state
        acc.balance = acc.balance.add(amount);
        emit CollateralDeposited(_NONCE, token, wid, amount);
        return actualAmount;
    }

    function addBatchCollateral(
        address wrappedToken,
        uint256[] memory wrappedIds,
        uint256[] memory amounts
    ) public isExec returns (uint256) {
        return _addBatchCollateral(wrappedToken, wrappedIds, amounts);
    }

    function _addBatchCollateral(
        address token,
        uint256[] memory wids,
        uint256[] memory amounts
    ) internal returns (uint256) {
        Account storage acc = _accounts[getExecutingNonce()];
        if (acc.wrappedToken != token) {
            console.log("initializing collateral");
            _initializeCollateral(acc, token, wids[0]);
        }

        console.log("pull wrapped tokens");
        // Pull the tokens
        uint256 actualAmount = _pullBatchWrappedTokens(token, wids, amounts);
        require(actualAmount > 0, "House: ADD_ZERO");
        console.log("add to account balance");
        // Add the tokens to the executing account state
        //acc.balance = acc.balance.add(amount); //FIX
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
        console.log("acc balance", acc.balance);
        require(acc.balance == uint256(0), "House: INITIALIZED");
        console.log("setting account wrapped token and id");
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
        console.log("house: internal removal");
        // Remove wrappedTokens from account state
        bool success = _removeCollateral(wrappedToken, wrappedId, amount);
        console.log("house: safetransferfrom this to msgsender");
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
        console.log("checking wrapped token and id");
        require(acc.wrappedId == wip, "House: INVALID_ID");
        require(acc.wrappedToken == token, "House: INVALID_TOKEN");
        uint256 balance = acc.balance;
        if (amount == uint256(-1)) {
            amount = balance;
        }
        console.log("house: acc.balance sub amount", acc.balance, amount);
        acc.balance = acc.balance.sub(amount);
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
        bytes32 oid,
        uint256 requestAmt,
        address[] memory receivers
    ) public isExec returns (uint256) {
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
        // Get the Account to manipulate
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
        _NONCE = accountNonce;
        _VENUE = venue;
        _accelerator.executeCall(venue, params);
        _NONCE = _NO_NONCE;
        _VENUE = _NO_ADDRESS;
        emit Executed(msg.sender, venue);
        return true;
    }

    // ===== Option Hooks =====

    function exercise(
        bytes32 oid,
        uint256 amount,
        address receiver,
        bool fromInternal
    ) external isExec returns (bool) {
        // If exercising from an internal balance, use the Venue's balance of tokens.
        if (fromInternal) {
            _EXECUTING_SENDER = getExecutingVenue();
        }
        exercise(oid, amount, receiver);
        _EXECUTING_SENDER = _NO_ADDRESS;
        return true;
    }

    function redeem(
        bytes32 oid,
        uint256 amount,
        address receiver,
        bool fromInternal
    ) external isExec returns (bool) {
        // If redeeming from an internal balance, use the Venue's balance of tokens.
        if (fromInternal) {
            _EXECUTING_SENDER = getExecutingVenue();
        }
        redeem(oid, amount, receiver);
        _EXECUTING_SENDER = _NO_ADDRESS;
        return true;
    }

    function close(
        bytes32 oid,
        uint256 amount,
        address receiver,
        bool fromInternal
    ) external isExec returns (bool) {
        // If closing from an internal balance, use the Venue's balance of tokens.
        if (fromInternal) {
            _EXECUTING_SENDER = getExecutingVenue();
        }
        close(oid, amount, receiver);
        _EXECUTING_SENDER = _NO_ADDRESS;
        return true;
    }

    /**
     * @notice  Hook to be implemented by higher-level Manager contract after minting occurs.
     */
    function _onAfterMint(
        bytes32 oid,
        uint256 amount,
        address[] memory receivers
    ) internal override isExec returns (bool) {
        // Update internal base token balance
        (address baseToken, , , , ) = getParameters(oid);
        console.log("got parameters", baseToken);
        // Update houseBalance
        _collateralBalance[baseToken] = _collateralBalance[baseToken].add(
            amount
        );

        console.log("pull base tokens from caller");
        // pull the base tokens from acc.depositor
        IERC20(baseToken).safeTransferFrom(
            getExecutingCaller(),
            address(this),
            amount
        );
        return true;
    }

    /*
     * @notice Hook to be implemented by higher-level Manager contract before exercising occurs.
     */
    function _onBeforeExercise(
        bytes32 oid,
        uint256 amount,
        address receiver
    ) internal override returns (bool) {
        (address baseToken, , , , ) = getParameters(oid);
        console.log("checking is not expired");
        require(notExpired(oid), "House: EXPIRED_OPTION");

        console.log("subtracting base claim");
        // Update claim for base tokens
        _collateralBalance[baseToken] -= amount;

        console.log("pushing base tokens");
        // Push base tokens
        IERC20(baseToken).safeTransfer(receiver, amount);

        console.log("_core.dangerousExercise");
        return true;
    }

    /**
     * @notice  Hook to be implemented by higher-level Manager contract after exercising occurs.
     */
    function _onAfterExercise(
        bytes32 oid,
        uint256 amount,
        address receiver,
        uint256 lessBase,
        uint256 plusQuote
    ) internal override returns (bool) {
        (, address quoteToken, , , ) = getParameters(oid);
        // Update claim for quote tokens
        _collateralBalance[quoteToken] += plusQuote;
        console.log("pulling quote tokens");
        // Pulls quote tokens
        Account storage acc = _accounts[getExecutingNonce()];
        //address pullFrom = fromInternal ? msg.sender : acc.depositor;
        // fromInternal ? getExecutingVenue : getExecutingCaller
        IERC20(quoteToken).safeTransferFrom(
            _getExecutingSender(),
            address(this),
            plusQuote
        );
        return true;
    }

    /**
     * @notice  Hook to be implemented by higher-level Manager contract before redemption occurs.
     */
    function _onBeforeRedeem(
        bytes32 oid,
        uint256 amount,
        address receiver
    ) internal override returns (uint256, uint256) {
        (, address quoteToken, uint256 strikePrice, , ) = getParameters(oid);
        (, address short) = _core.getTokenData(oid);
        console.log("checking is not expired");
        require(notExpired(oid), "House: EXPIRED_OPTION");
        // if not from internal, pull short options from caller to venue
        if (_getExecutingSender() == getExecutingCaller()) {
            console.log("taking tokens from user");
            _takeTokensFromUser(short, amount);
        }

        uint256 quoteClaim = _collateralBalance[quoteToken];
        uint256 minOutputQuote = amount.mul(strikePrice).div(1 ether);
        console.log("calling core.dangerousredeem");
        return (minOutputQuote, quoteClaim);
    }

    /**
     * @notice  Hook to be implemented by higher-level Manager contract after redemption occurs.
     */
    function _onAfterRedeem(
        bytes32 oid,
        uint256 amount,
        address receiver,
        uint256 lessQuote
    ) internal override returns (bool) {
        console.log("subtracting base claim");
        (, address quoteToken, , , ) = getParameters(oid);
        // Update claim for quoteTokens
        _collateralBalance[quoteToken] -= lessQuote;

        console.log("pushing quote tokens");
        // Push base tokens
        IERC20(quoteToken).safeTransfer(receiver, lessQuote);
        return true;
    }

    /**
     * @notice  Hook to be implemented by higher-level Manager contract before closing occurs.
     */
    function _onBeforeClose(
        bytes32 oid,
        uint256 amount,
        address receiver
    ) internal override returns (bool) {
        (address long, address short) = _core.getTokenData(oid);
        console.log("checking is not expired");
        require(notExpired(oid), "House: EXPIRED_OPTION");
        // if not from internal, pull short options from caller to venue
        if (_getExecutingSender() == getExecutingCaller()) {
            console.log("take long and short from user");
            _takeTokensFromUser(short, amount);
            _takeTokensFromUser(long, amount);
        }
        console.log("calling core.dangerousclose");
        return true;
    }

    /**
     * @notice  Hook to be implemented by higher-level Manager contract after closing occurs.
     */
    function _onAfterClose(
        bytes32 oid,
        uint256 amount,
        address receiver,
        uint256 lessBase
    ) internal override returns (bool) {
        (address baseToken, , , , ) = getParameters(oid);
        console.log("subtracting base claim");
        // Update claim for baseTokens
        _collateralBalance[baseToken] -= lessBase;

        console.log("pushing base tokens");
        // Push base tokens
        IERC20(baseToken).safeTransfer(receiver, lessBase);
        return true;
    }

    // ===== View =====

    /**
     * @notice  A mutex that is set when the `execute` fn is called.
     * @dev     Reset after execute to false.
     */
    function isExecuting() public view returns (bool) {
        return _EXECUTING;
    }

    /**
     * @notice  The accountNonce which is being manipulated by the currently executing `execute` fn.
     * @dev     Reset after execute to _NO_NONCE.
     */
    function getExecutingNonce() public view returns (uint256) {
        return _NONCE;
    }

    /**
     * @notice  The `msg.sender` of the `execute` fn.
     * @dev     Reset after execute to _NO_ADDRESS.
     */
    function getExecutingCaller() public view returns (address) {
        return _accounts[getExecutingNonce()].depositor;
    }

    /**
     * @notice  The venue that is the `target` address of the `execute` fn.
     * @dev     Reset after execute to _NO_ADDRESS.
     */
    function getExecutingVenue() public view returns (address) {
        return _VENUE;
    }

    /**
     * @notice  Fetches the current account nonce, which will be the nonce of the next Account.
     */
    function getAccountNonce() public view returns (uint256) {
        return _accountNonce;
    }

    /**
     * @notice  Fetches the Account struct objects.
     */
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

    /**
     * @notice  Fetches the Accelerator contract.
     * @dev     Accelerator is an intemediary to execute the `execute` fn on behalf of this contract.
     */
    function getAccelerator() public view returns (address) {
        return address(_accelerator);
    }

    // === View Hooks ===

    /**
     * @notice  If `_EXECUTING_SENDER` is `_NO_ADDRESS`, use Account.depositor, else use the `_VENUE`.
     * @dev     Overrides the virtual hook in abstract Manager contract.
     */
    function _getExecutingSender() internal view override returns (address) {
        return
            _EXECUTING_SENDER == _NO_ADDRESS
                ? getExecutingCaller()
                : getExecutingVenue();
    }

    /**
     * @notice  Returns true if the expiry timestamp of an option is greater than or equal to current timestamp.
     * @dev     Overrides the virtual hook in abstract Manager contract.
     */
    function _notExpired(bytes32 oid) internal view override returns (bool) {
        (, , , uint32 expiry, ) = getParameters(oid);
        return expiry >= block.timestamp;
    }
}
