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
import {IFlash} from "./interfaces/IFlash.sol";

// Internal
import {Accelerator} from "./Accelerator.sol";
import {ICapitol} from "./interfaces/ICapitol.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IHouse} from "./interfaces/IHouse.sol";
import {IWETH} from "./interfaces/IWETH.sol";
import {SafeMath} from "./libraries/SafeMath.sol";

import {Manager} from "./Manager.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

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
     * @dev The venue registry contract.
     */
    ICapitol internal _capitol;

    /**
     * @dev The contract with core option logic.
     */
    IOptionCore internal _core;

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
        require(_capitol.getIsEndorsed(venue_), "House: NOT_ENDORSED");
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

    constructor(address capitol_, address optionCore_) {
        _capitol = ICapitol(capitol_);
        _accelerator = new Accelerator();
        _core = IOptionCore(optionCore_);
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
        (bool success, uint256 actual) =
            _core.dangerousMint(oid, requestAmt, receivers);

        // Update internal base token balance
        (address baseToken, , , , ) = _core.getParameters(oid);
        uint256 newBalance = _universalDebt[baseToken].add(actual);
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
    ) public isEndorsed(msg.sender) isExec returns (bool, uint256) {
        // Get the account that is being updated
        Account storage acc = _accounts[getExecutingNonce()];
        // Update the acc delta
        acc.delta = requestAmt;
        // Update acc debt balance
        acc.balance = acc.balance.add(requestAmt);
        (bool success, uint256 actualAmt) =
            _core.dangerousMint(oid, requestAmt, receivers);
        // Reset delta by subtracting from actual amount borrowed
        acc.delta = actualAmt.sub(acc.delta);
        return (success, actualAmt);
    }

    /**
     * @notice  Burns option ERC20 tokens from the `holders` address(es).
     * @param   oid The option data id used to fetch option related data.
     * @param   requestAmt The amount of long and short option ERC20 tokens to burn.
     * @param   holders The address to burn long option ERC20 from, and address to burn short option ERC20 from.
     * @return  Whether or not the burn succeeded.
     */
    function burnOptions(
        bytes memory oid,
        uint256 requestAmt,
        address[] memory holders
    ) public isEndorsed(msg.sender) isExec returns (bool) {
        // Get the account that is being updated
        Account storage acc = _accounts[getExecutingNonce()];
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = requestAmt;
        // Set the delta to the requestAmt so that the invariant will check if the burn amount matches.
        acc.delta = requestAmt;
        // Burn the options.
        _core.dangerousBurn(oid, amounts, holders);
        // Update the underlying debt by subtracting the option requestAmt
        uint256 accDebt = acc.debt;
        // if request is greater than debt, set debt to 0
        acc.debt = requestAmt > accDebt ? uint256(0) : accDebt.sub(requestAmt);
        // Update internally tracked baseToken balance
        (address baseToken, , , , ) = _core.getParameters(oid);
        _internalUpdate(baseToken, _universalDebt[baseToken].sub(requestAmt));
        // Reset the account delta
        acc.delta = 0;
        return true;
    }

    /**
     * @notice  Exercise option ERC20 tokens from the `holders` address(es).
     * @dev     If not expired, burns long options, pulls strikePrice, and releases underlying.
     *          If expired, cannot be executed.
     * @param   oid The option data id used to fetch option related data.
     * @param   requestAmt The requestAmt of long and short option ERC20 tokens to burn.
     * @param   holders The address to burn long option ERC20 from, and address to burn short option ERC20 from.
     * @return  Whether or not the burn succeeded.
     */
    function exerciseOptions(
        address receiver,
        bytes memory oid,
        uint256 requestAmt,
        address[] memory holders,
        bytes memory data
    ) public isEndorsed(msg.sender) isExec returns (bool) {
        // Get the account that is being updated
        Account storage acc = _accounts[getExecutingNonce()];
        require(expiryInvariant(oid), "House: EXERCISE_INVARIANT");

        // Store params in memory for gas savings
        (address baseToken, address quoteToken, , , ) =
            _core.getParameters(oid);

        (, address shortOption) = _core.getTokenData(oid);

        // Optimistically transfer base ERC20 tokens to receiver
        IERC20(baseToken).safeTransfer(receiver, requestAmt);
        // Trigger flash callback if data argument exists
        if (data.length > 0)
            IFlash(receiver).primitiveFlash(msg.sender, requestAmt, data);

        // Burn `requestAmt` of long options.
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = requestAmt;
        // Burn the options, which will call the respective invariant() functions in this contract.
        _core.dangerousBurn(oid, amounts, holders);

        // Get the current base and quote token balances
        uint256 currBal = IERC20(baseToken).balanceOf(address(this));
        uint256 currQuoteBal = IERC20(quoteToken).balanceOf(address(this));

        // this is 3xSStores, expensive

        // Update both token balances
        _internalUpdate(baseToken, currBal);
        // Update claimable quote tokens
        _quoteClaimUpdate(
            shortOption,
            quoteToken,
            currQuoteBal.sub(_universalDebt[quoteToken])
        );
        // Update internal quote balance
        _internalUpdate(quoteToken, currQuoteBal);
        return true;
    }

    /**
     * @notice Optimistically releases base and quote tokens, then burns the required amount of options.
     */
    function closeOptions(
        bytes memory oid,
        uint256[] memory amounts,
        address[] memory receivers,
        address[] memory holders
    ) public isEndorsed(msg.sender) isExec returns (bool) {
        // Optimistically transfer out amounts
        // Get the account that is being updated
        Account storage acc = _accounts[getExecutingNonce()];

        // Store params in memory for gas savings
        (address baseToken, address quoteToken, uint256 strikePrice, , ) =
            _core.getParameters(oid);

        (address longToken, address shortToken) = _core.getTokenData(oid);

        uint256 quoteClaim = _quoteClaim[shortOption][quoteToken];
        uint256 shortSupply = IERC20(shortToken).totalSupply();
        uint256 longSupply = IERC20(longToken).totalSupply();

        // Check to make sure the amount of base tokens can be sent out.
        uint256 product = shortSupply.mul(longSupply).mul(strikePrice); // x * y * s = z
        uint256 quoteProduct = quoteClaim.mul(shortSupply); // q * x = w
        uint256 baseProduct = product.sub(quoteProduct); // z - w = b
        uint256 baseClaim = baseProduct.div(longSupply); // b / y = i
        uint256 scaledBaseClaim = baseClaim.div(strikePrice); // i / s = c

        // Get the output amounts to transfer out. Quote tokens are scaled to be in denominations of the quote.
        uint256 outputBase = amounts[0].mul(scaledBaseClaim).div(longSupply);
        uint256 outputQuote = amounts[1].mul(quoteClaim).div(shortSupply);
        require(
            scaledBaseClaim >= outputBase && quoteClaim >= outputQuote,
            "House: OUTPUTS"
        );

        IERC20(baseToken).safeTransfer(receivers[0], outputBase);
        IERC20(quoteToken).safeTransfer(receivers[1], outputQuote);

        // Set the delta to the requestAmt so that the invariant will check if the burn amount matches.
        acc.delta = outputBase;

        // Execute the burn, which checks settlement invariants
        _core.dangerousBurn(oid, amounts, holders);

        // Get the current base and quote token balances
        uint256 currBal = IERC20(baseToken).balanceOf(address(this));
        uint256 currQuoteBal = IERC20(quoteToken).balanceOf(address(this));

        // Update the underlying debt by subtracting the option requestAmt
        uint256 accDebt = acc.debt;
        // if request is greater than debt, set debt to 0
        acc.debt = outputBase > accDebt ? uint256(0) : accDebt.sub(outputBase);
        // Reset the account delta
        acc.delta = 0;

        // Update internal base and quote token balances
        _internalUpdate(baseToken, currBal);
        // Update claimable quote tokens
        _quoteClaimUpdate(shortOption, quoteToken, quoteClaim.sub(outputQuote));
        // Update internal quote balance
        _internalUpdate(quoteToken, currQuoteBal);
        return true;
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

    // @notice  A stub of the invariant rule which is called when option burning occurs.
    function burningInvariant(bytes calldata oid, uint256[] calldata amounts)
        external
        view
        override
        returns (bool)
    {
        return false;
    }

    // @notice  A stub of the invariant rule which is called when settlement occurs.
    function settlementInvariant(bytes calldata oid)
        external
        view
        override
        returns (bool)
    {
        return false;
    }

    /**
     * @notice  An invartiant rule implementation which is called by `_core` when option minting occurs.
     * @dev     Warning: this implementation is critical to the solvency of the option tokens.
     * @param   oid The option id which will be used for checking the invariants.
     * @param   requestAmt The requestAmt of options being requested to be minted.
     * @return  Whether or not the invariant checks succeeded.
     */
    function mintingInvariant(bytes memory oid, uint256 requestAmt)
        public
        override
        isExec
        returns (bool, uint256)
    {
        require(expiryInvariant(oid), "House: EXPIRED");
        // if not expired
        (address baseToken, , , , ) = _core.getParameters(oid);
        // Check the previous baseToken balance against the current balance.
        uint256 prevBal = _universalDebt[baseToken];
        uint256 currBal = IERC20(baseToken).balanceOf(address(this));
        uint256 actualAmt = currBal.sub(prevBal);
        // If there's a difference, return true and the actualAmt.
        bool internalUpdated = actualAmt >= requestAmt;
        // Fail early if this contract does not have enough base tokens
        require(currBal >= requestAmt, "House: MINT_AMOUNT");
        // If there is no actualAmt, require the acc delta to be greater than 0, and return delta as actualAmt
        if (!internalUpdated) {
            Account memory acc = _accounts[_NONCE];
            uint256 delta = acc.delta;
            return (delta > 0, delta);
        }
        return (internalUpdated, actualAmt);
    }

    /**
     * @notice  An invartiant rule implementation which is called by `_core` when option operations occur.
     * @dev     Warning: this implementation is critical to the solvency of the option tokens.
     * @param   oid The option id which will be used for checking the invariants.
     * @return  Whether or not the invariant checks succeeded.
     */
    function expiryInvariant(bytes memory oid)
        public
        view
        override
        returns (bool)
    {
        (, , , uint8 expiry, ) = _core.getParameters(oid);
        bool notExpired = expiry >= block.timestamp;
        return notExpired;
    }

    /**
     * @notice  An invariant that is checked when long option tokens are requested to be burned.
     */
    function exerciseInvariant(bytes memory oid, uint256 actualAmt)
        public
        view
        override
        returns (bool)
    {
        // Exercise:    Burn long, Receive `amount`*strikePrice quoteTokens, Push `amount` baseTokens
        // Get the parameters of the option
        (address baseToken, address quoteToken, uint256 strikePrice, , ) =
            _core.getParameters(oid);

        // Check to see if underlying tokens were paid.
        uint256 prevBal = _universalDebt[baseToken];
        uint256 currBal = IERC20(baseToken).balanceOf(address(this));

        // Check to see if strikePrice were paid.
        uint256 prevQuoteBal = _universalDebt[quoteToken];
        uint256 currQuoteBal = IERC20(quoteToken).balanceOf(address(this));

        // IMPORTANT: Require baseTokenDiff + quoteTokenDiff.div(strikePrice) >= actualAmt

        // Calculate the differences.
        uint256 inputQuote = currQuoteBal.sub(prevQuoteBal);
        uint256 inputBase = currBal.sub(prevBal.sub(actualAmt)); // will be > 0 if baseTokens are returned.

        // Either baseTokens or quoteTokens must be sent into the contract.
        require(inputQuote > 0 || inputBase > 0, "House: NO_PAYMENT");

        // Calculate the remaining amount of baseTokens that needs to be paid for.
        uint256 remainder =
            inputBase > actualAmt ? 0 : actualAmt.sub(inputBase);

        // Calculate the expected payment of quoteTokens.
        uint256 payment = remainder.mul(strikePrice).div(1 ether);

        // Enforce the invariants.
        require(inputQuote >= payment, "House: QUOTE_PAYMENT");
        return true;
    }

    /**
     * @notice  An invariant that is checked when short option tokens are requested to be burned.
     */
    function settleInvariant(bytes memory oid, uint256 shortBurned)
        public
        view
        returns (bool)
    {
        // Settle:      Burn short, push remaining base and quote tokens.

        // If the option is expired, push base and quote tokens remaining.
        // Else, only push quote tokens.
        (address baseToken, address quoteToken, uint256 strikePrice, , ) =
            _core.getParameters(oid);
        (address longToken, address shortToken) = _core.getTokenData(oid);

        bool notExpired = expiryInvariant(oid);

        // Actual balances
        uint256 baseBalance = IERC20(baseToken).balanceOf(address(this));
        uint256 quoteBalance = IERC20(quoteToken).balanceOf(address(this));

        // Stored balances
        uint256 prevBaseBal = _universalDebt[baseToken];
        uint256 prevQuoteBal = _universalDebt[quoteToken];

        // Total supply
        uint256 longSupply = IERC20(longToken).totalSupply();
        uint256 shortSupply = IERC20(shortToken).totalSupply();

        // Quote claim
        uint256 quoteClaim = _quoteClaim[shortToken][quoteToken];
        uint256 baseClaim;
        {
            uint256 product = shortSupply.mul(longSupply).mul(strikePrice); // x * y * s = z
            uint256 quoteProduct = quoteClaim.mul(shortSupply); // q * x = w
            uint256 baseProduct = product.sub(quoteProduct); // z - w = b
            uint256 unscaledBaseClaim = baseProduct.div(longSupply); // b / y = i
            uint256 scaledBaseClaim = unscaledBaseClaim.div(strikePrice); // i / s = c
            baseClaim = scaledBaseClaim;
        }

        // Current balances should be less than stored balances, since tokens were sent out prior to this call.
        uint256 outputBase = prevBaseBal.sub(baseBalance);
        uint256 outputQuote = prevQuoteBal.sub(quoteBalance);

        // There are two settlements: post-expiry and pre-expiry.
        // Pre-expiry settlement only occurs for American options, in the case where exercises happened early.
        //
        // For an option to be **pre-expiry settled**, there must be:
        //
        // claimable quote tokens = quoteTokensRedeemed * shortSupply / shortBurned
        //
        // For an option to be **post-expiry settled**, there must be:
        //
        // claimable quote tokens = quoteTokensRedeemed * shortSupply / shortBurned
        //
        // claimable base tokens = baseTokensRedeemed * shortSupply/ shortBurned

        // If expired, then base and quote tokens have been released.
        if (!notExpired) {
            require(
                baseClaim == outputBase.mul(shortSupply).div(shortBurned),
                "House: BASE_INPUT"
            );
        }

        // If not expired, then only quote tokens have been released.
        require(
            quoteClaim == outputQuote.mul(shortSupply).div(shortBurned),
            "House: QUOTE_INPUT"
        );

        return true;
    }

    /**
     * @notice  An invartiant which is called by `_core` when long + short option tokens are being burned.
     * @dev     Warning: this implementation is critical to the solvency of the option tokens.
     * @param   oid The option id which will be used for checking the invariants.
     * @param   amounts The amounts of [long, short] options to burn.
     * @return  Whether or not the invariant checks succeeded.
     */
    function closeInvariant(bytes memory oid, uint256[] memory amounts)
        public
        override
        isExec
        returns (bool)
    {
        // Close        Burn long and short, require(!notExpired), push `amount` base tokens.
        uint256 amount0 = amounts[0];
        uint256 amount1 = amounts[1];

        // Get the parameters of the option
        (address baseToken, address quoteToken, uint256 strikePrice, , ) =
            _core.getParameters(oid);

        uint256 prevBal = _universalDebt[baseToken];
        uint256 currBal = IERC20(baseToken).balanceOf(address(this));

        Account storage acc = _accounts[getExecutingNonce()];
        require(acc.delta >= amount0, "House: CLOSE_FAIL");

        return expiryInvariant(oid);
    }

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

    function getCapitol() public view returns (address) {
        return address(_capitol);
    }

    function getAccelerator() public view returns (address) {
        return address(_accelerator);
    }
}
