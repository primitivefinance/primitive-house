// SPDX-License-Identifier: MIT
pragma solidity >=0.6.2;

/**
 * @title   The Primitive House contract base.
 * @author  Primitive
 */


import {SafeMath} from "./libraries/SafeMath.sol";
import {IPrimitiveERC20} from "./interfaces/IPrimitiveERC20.sol";
import {IOption} from "@primitivefi/contracts/contracts/option/interfaces/IOption.sol";
import {ISERC20} from "./interfaces/ISERC20.sol";
import {IVenue} from "./interfaces/IVenue.sol";

// Uni
import {
    IUniswapV2Callee
} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Callee.sol";
import {
    IUniswapV2Pair
} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";

contract House {
    using SafeERC20 for IERC20;
    using SafeERC20 for IOption;
    using SafeMath for uint256;

    struct ReserveData {
        ISERC20 syntheticToken;
    }

    event SyntheticMinted(
        address indexed from,
        address indexed optionAddress,
        uint256 quantity
    );

    event OpenedDebitSpread(
        address indexed from,
        address indexed longOption,
        address indexed shortOption,
        uint256 quantity
    );

    IRegistry public registry;

    mapping(address => mapping(address => uint)) public bank;
    mapping(address => address) public syntheticOptions;
    mapping(address => ReserveData) internal _reserves;

    // mutex
    bool private _notEntered;

    modifier nonReentrant() {
        require(notEntered == 1, "PrimitiveHouse: NON_REENTRANT");
        notEntered = true;
        _;
        notEntered = false;
    }

    constructor() public {}

    // Initialize self
    function initializeSelf(address registry_) external {
        registry = IRegistry(registry_);
    }

    function addSyntheticToken(address asset, address syntheticAsset) external {
        ISERC20(syntheticAsset).initialize(asset, address(this));
        ReserveData storage reserve = _reserves[asset];
        reserve.syntheticToken = ISERC20(syntheticAsset);
    }

    // Initialize a synthetic option
    function deploySyntheticOption(address optionAddress)
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
        // fix - this doubles the gas cost, maybe just make them synthetic?
        address syntheticOption = registry.deployOption(
            address(_reserves[underlying].syntheticToken),
            address(_reserves[strike].syntheticToken),
            baseValue,
            quoteValue,
            expiry
        );

        syntheticOptions[optionAddress] = syntheticOption;
        return syntheticOption;
    }

    // Open an account

    // LP

    /**
     * @dev     Mints short option tokens synthetically, to deposit them into the market. 
     * @notice  Hold LP tokens as collateral, attribute to original depositor.
     */
    function borrowWithLP(address depositor, address pair, address longOption, uint quantity) public {
        IOption syntheticLong = IOption(syntheticOptions[longOption]);

        // Get synthetic token from reserve.
        ReserveData storage reserve = _reserves[IOption(longOption)
            .getUnderlyingTokenAddress()];

        // Mint synthetic tokens to the synthetic short option.
        reserve.syntheticToken.mint(address(syntheticLong), quantity);

        // Mint synthetic option and redeem tokens to this contract.
        syntheticLong.mintOptions(address(this));

        // Send out synthetic short option tokens to the pair.
        address redeem = syntheticLong.redeemToken();
         IERC20(redeem).transfer(
            pair,
            IERC20(redeem).balanceOf(address(this))
        );

        // call mint() on the pair to receive LP tokens
        uint liquidity = IUniswapV2Pair(pair).mint(address(this));
        
        // get the balance of Lp tokens and attribute it to the original depositor
        bank[depositor][pair] = liquidity;

        // Final Balance Sheet
        //
        // House
        // quantity# of long option tokens
        // liquidity# of lp tokens
        //
        // Pair
        // balance# of redeem tokens
        // quantity# of underlying tokens
        //
        // Depositor
        // liquidity# of lp tokens held in this contract
    }

    function withdrawFromLP(address option, address pair, uint quantity) public {
        // get depositor balance of liquidity and send it to the pair
        uint liquidity = bank[msg.sender][pair];
        IERC20(pair).transfer(pair, liquidity);
        // update balance
        bank[msg.sender][pair] = 0;
        // get tokens from pair
        (uint amount0, uint amount1) = IUniswapV2Pair(pair).burn(address(this));
        address underlying = IOption(option).underlyingTokenAddress();
        address token0 = IUniswapV2Pair(pair).token0();
        address token1 = IUniswapV2Pair(pair).token1();
        uint assetAmt = token0 ==  underlying ? amount0 : amount1;
        uint shortAmt = token0 == underlying ? amount1 : amount0;

        // close the option, 4 transfers...
        IERC20(token0 == underlying ? token1: token0).transfer(option, assetAmt);
        IERC20(option).transfer(option, shortAmt);
        IOption(option).closeOptions(address(this));
        // Get synthetic token from reserve.
        ReserveData storage reserve = _reserves[underlying];
        // Burn synthetic tokens from this contract.
        reserve.syntheticToken.burn(address(this), assetAmt);

        // return the assets
        IERC20(underlying).transfer(msg.sender, asset);
    }

    // Position operations

    function openDebitSpread(
        address longOption,
        address shortOption,
        uint256 quantity,
        address receiver
    ) external {
        // assume these are calls for now
        IOption syntheticLong = IOption(syntheticOptions[longOption]);
        IOption syntheticShort = IOption(syntheticOptions[shortOption]);

        // Check to make sure long option sufficiently covers short option.
        uint256 longStrike = syntheticLong.getQuoteValue();
        uint256 shortStrike = syntheticShort.getQuoteValue();
        require(shortStrike >= longStrike, "ERR_CREDIT_SPREAD");

        // e.g. short a 500 call and long a 400 call. 100 strike difference.
        uint256 strikeDifference = shortStrike.sub(longStrike);

        // Get synthetic token from reserve.
        ReserveData storage reserve = _reserves[IOption(shortOption)
            .getUnderlyingTokenAddress()];

        // Mint synthetic tokens to the synthetic short option.
        reserve.syntheticToken.mint(address(syntheticShort), quantity);

        // Mint synthetic option and redeem tokens to this contract.
        syntheticShort.mintOptions(address(this));

        // Send out synthetic option tokens.
        syntheticShort.transfer(receiver, quantity);

        // Send out strikeDifference quantity of synthetic redeem tokens.
        IERC20(syntheticShort.redeemToken()).transfer(
            receiver,
            strikeDifference
        );

        // Pull in the original long option.
        syntheticLong.safeTransferFrom(msg.sender, address(this), quantity);

        emit OpenedDebitSpread(msg.sender, longOption, shortOption, quantity);

        // Final balance sheet:
        //
        // House
        // Quantity# of long option tokens
        // strikeDiff# of synthetic short option (redeem) tokens
        //
        // Receiver
        // Quantity# of synthetic long option tokens (which can then be sold)
        // 1 - strikeDiff# of synthetic short option (redeem) tokens
    }

    // Option operations

    function syntheticMint(
        address optionAddress,
        uint256 quantity,
        address receiver
    ) external returns (address) {
        address syntheticOption = syntheticOptions[optionAddress];
        require(syntheticOption != address(0x0), "ERR_NOT_DEPLOYED");

        // Store in memory for gas savings.
        address underlying = IOption(optionAddress).getUnderlyingTokenAddress();

        // Get synthetic token from reserve.
        ReserveData storage reserve = _reserves[underlying];

        // Mint synthetic tokens to the synthetic option contract.
        reserve.syntheticToken.mint(syntheticOption, quantity);

        // Call mintOptions and send options to the receiver address.
        IOption(syntheticOption).mintOptions(receiver);

        // Pull real tokens to this contract.
        _pullTokens(underlying, quantity);

        emit SyntheticMinted(msg.sender, optionAddress, quantity);
        return syntheticOption;
    }

    function syntheticExercise(
        address optionAddress,
        uint256 quantity,
        address receiver
    ) external {
        address syntheticOption = syntheticOptions[optionAddress];
        require(syntheticOption != address(0x0), "ERR_NOT_DEPLOYED");

        // Store in memory for gas savings.
        address underlying = IOption(optionAddress).getUnderlyingTokenAddress();
        address strike = IOption(optionAddress).getStrikeTokenAddress();

        // Move synthetic options from msg.sender to synthetic option contract itself.
        IERC20(syntheticOption).safeTransferFrom(
            msg.sender,
            syntheticOption,
            quantity
        );

        // Calculate strike tokens needed to exercise.
        uint256 amountStrikeTokens = calculateStrikePayment(
            optionAddress,
            quantity
        );

        // Mint required strike tokens to the synthetic option in preparation of calling exerciseOptions().
        _reserves[strike].syntheticToken.mint(
            syntheticOption,
            amountStrikeTokens
        );

        // Call exerciseOptions and send underlying tokens to this contract.
        IOption(syntheticOption).exerciseOptions(
            address(this),
            quantity,
            new bytes(0)
        );

        // Burn the synthetic underlying tokens.
        _reserves[underlying].syntheticToken.burn(address(this), quantity);

        // Push real underlying tokens to receiver.
        IERC20(underlying).safeTransfer(receiver, quantity);

        // Pull real strike tokens to this contract.
        IERC20(strike).safeTransferFrom(
            msg.sender,
            address(this),
            amountStrikeTokens
        );
    }

    function calculateStrikePayment(address optionAddress, uint256 quantity)
        public
        view
        returns (uint256)
    {
        uint256 baseValue = IOption(optionAddress).getBaseValue();
        uint256 quoteValue = IOption(optionAddress).getQuoteValue();

        // Parameter `quantity` is in units of baseValue. Convert it into units of quoteValue.
        uint256 calculatedValue = quantity.mul(quoteValue).div(baseValue);
        return calculatedValue;
    }

    function _pullTokens(address token, uint256 quantity) internal {
        IERC20(token).safeTransferFrom(msg.sender, address(this), quantity);
    }

}


