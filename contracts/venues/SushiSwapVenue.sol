pragma solidity >=0.6.2;

// Open Zeppelin
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

// Primitive
import {
    ISushiSwapVenue,
    IUniswapV2Router02,
    IUniswapV2Factory,
    IOption,
    IERC20
} from "../interfaces/ISushiSwapVenue.sol";

// Internal
import {BaseVenue} from "../BaseVenue.sol";
import {ICapitol} from "../interfaces/ICapitol.sol";
import {IHouse} from "../interfaces/IHouse.sol";
import {IWETH} from "../interfaces/IWETH.sol";
import {SafeMath} from "../libraries/SafeMath.sol";
import {RouterLib} from "../libraries/RouterLib.sol";
import {Venue} from "../Venue.sol";

contract SushiSwapVenue is
    BaseVenue, /* Venue, */
    ISushiSwapVenue
{
    using SafeERC20 for IERC20; // Reverts when `transfer` or `transferFrom` erc20 calls don't return proper data
    using SafeMath for uint256; // Reverts on math underflows/overflows

    IUniswapV2Factory public override factory =
        IUniswapV2Factory(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f); // The Uniswap V2 factory contract to get pair addresses from
    IUniswapV2Router02 public override router =
        IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D); // The Uniswap contract used to interact with the protocol

    ICapitol public capitol;

    event Initialized(address indexed from); // Emmitted on deployment

    // ==== Constructor ====

    constructor(
        address weth_,
        address house_,
        address capitol_
    ) public BaseVenue(weth_, house_) {
        house = IHouse(house_);
        capitol = ICapitol(capitol_);
        emit Initialized(msg.sender);
    }

    // ==== Simple ====
    function pool(address option) public view returns (address) {
        address underlying = IOption(option).getUnderlyingTokenAddress();
        address redeem = IOption(option).redeemToken();
        address pair = factory.getPair(underlying, redeem);
        return pair;
    }

    function getApprovedPool(address option)
        public
        override(ISushiSwapVenue)
        returns (address)
    {
        address underlying = IOption(option).getUnderlyingTokenAddress();
        address redeem = IOption(option).redeemToken();
        address pair = factory.getPair(underlying, redeem);
        checkApproved(underlying, address(router));
        checkApproved(redeem, address(router));
        checkApproved(pair, address(router));
        return pair;
    }

    // User will enter pool with various amounts of leverage.

    /**
     * @dev     Convert assets to options liquidity.
     * @param   options The option addresses to deposit to.
     * @param   maxAmounts Per option: [optionsToMint, underlyingToDeposit]
     * @param   minAmounts Per option: [proportional(optionsToMint), minUnderlyingToDeposit]
     */
    function deposit(
        address[] memory options,
        uint256[] memory maxAmounts,
        uint256[] memory minAmounts,
        address receiver,
        uint256 deadline
    ) public override(ISushiSwapVenue) returns (uint256) {
        uint256 optionsLength = options.length;
        uint256 maxAmountsLength = maxAmounts.length;
        uint256 minAmountsLength = minAmounts.length;
        // require 2 maxAmounts and minAmounts per option, and ensure maxAmounts = minAmounts lengths.
        require(
            optionsLength == maxAmountsLength.div(2) &&
                maxAmountsLength == minAmountsLength,
            "UniswapVenue: ARRAY_LENGTHS"
        );

        uint256[] memory liquidityAmounts = new uint256[](optionsLength);
        address[] memory pairTokens = new address[](optionsLength);

        for (uint256 i = 0; i < optionsLength; i++) {
            address optionAddress = options[i];
            address pair = pool(optionAddress);
            uint256 optionsToMint = maxAmounts[i];
            uint256 underlyingDeposit = maxAmounts[i + 1];
            uint256 shortOptionsToMint =
                RouterLib.getProportionalShortOptions(
                    IOption(optionAddress),
                    optionsToMint
                );
            require(
                shortOptionsToMint == minAmounts[i],
                "UniswapVenue: SHORT_OPTIONS_INPUT"
            );
            uint256 minUnderlyingDeposit = minAmounts[i + 1];
            AddLiquidityParams memory params =
                AddLiquidityParams(
                    optionsToMint,
                    underlyingDeposit,
                    minUnderlyingDeposit,
                    now
                );
            // Adds liquidity to Uniswap V2 Pair and returns liquidity shares to this contract.
            (uint256 amountA, uint256 amountB, uint256 liquidity) =
                _addLiquidity(optionAddress, params);
            // Inputs for lending multiple tokens
            liquidityAmounts[i] = liquidity;
            pairTokens[i] = pair;
            // check for dust
            _takeDust(IOption(optionAddress).getUnderlyingTokenAddress());
            _takeDust(IOption(optionAddress).redeemToken());
        }
        // Add as collateral to the House.
        _lendMultiple(pairTokens, liquidityAmounts);
        // check for weth dust
        _takeWETHDust();
        return 1;
    }

    /**
     * @dev     Convert option liquidity into assets.
     * @param   options The option addresses to withdraw from.
     * @param   quantities Per option: [liquidityToBurn]
     * @param   minAmounts Per option: [minShortOptionsWithdrawn, minUnderlyingWithdrawn]
     */
    function withdraw(
        address[] memory options,
        uint256[] memory quantities,
        uint256[] memory minAmounts,
        address receiver,
        uint256 deadline
    ) public override(ISushiSwapVenue) returns (uint256) {
        uint256 optionsLength = options.length;
        uint256 quantitiesLength = quantities.length;
        uint256 minAmountsLength = minAmounts.length;
        // require 2 minAmounts per option, and ensure quantities = options lengths.
        require(
            optionsLength == quantitiesLength &&
                quantitiesLength == minAmountsLength.div(2),
            "UniswapVenue: ARRAY_LENGTHS"
        );

        address[] memory liquidityPools = new address[](optionsLength);
        for (uint256 i = 0; i < optionsLength; i++) {
            address optionAddress = options[i];
            address pair = pool(optionAddress);
            liquidityPools[i] = pair;
        }

        _borrowMultiple(liquidityPools, quantities);

        for (uint256 i = 0; i < optionsLength; i++) {
            address optionAddress = options[i];
            uint256 liquidityToBurn = quantities[i];
            uint256 minimumShortOptions = minAmounts[i];
            uint256 minimumUnderlyingTokens = minAmounts[i + 1];
            address pair = liquidityPools[i];
            // Remove liquidity
            RemoveLiquidityParams memory params =
                RemoveLiquidityParams(
                    liquidityToBurn,
                    minimumShortOptions,
                    minimumUnderlyingTokens,
                    deadline
                );
            _removeLiquidity(optionAddress, params);
        }

        return 1;
    }

    // ==== Liquidity Functions ====

    struct AddLiquidityParams {
        uint256 quantityOptions;
        uint256 amountBMax;
        uint256 amountBMin;
        uint256 deadline;
    }

    /**
     * @dev    Adds redeemToken liquidity to a redeem<>underlyingToken pair by minting shortOptionTokens with underlyingTokens.
     * @notice Pulls underlying tokens from msg.sender and pushes UNI-V2 liquidity tokens to the "to" address.
     *         underlyingToken -> redeemToken -> UNI-V2.
     * @param optionAddress The address of the optionToken to get the redeemToken to mint then provide liquidity for.
     * @param quantityOptions The quantity of underlyingTokens to use to mint option + redeem tokens.
     * @param amountBMax The quantity of underlyingTokens to add with shortOptionTokens to the Uniswap V2 Pair.
     * @param amountBMin The minimum quantity of underlyingTokens expected to provide liquidity with.
     * @param to The address that receives UNI-V2 shares.
     * @param deadline The timestamp to expire a pending transaction.
     */
    function addShortLiquidityWithUnderlying(
        address optionAddress,
        uint256 quantityOptions,
        uint256 amountBMax,
        uint256 amountBMin,
        address to,
        uint256 deadline
    )
        external
        payable
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        address pair = pool(optionAddress);
        AddLiquidityParams memory params =
            AddLiquidityParams(
                quantityOptions,
                amountBMax,
                amountBMin,
                deadline
            );
        // Adds liquidity to Uniswap V2 Pair and returns liquidity shares to this contract.
        (uint256 amountA, uint256 amountB, uint256 liquidity) =
            _addLiquidity(optionAddress, params);

        // Add as collateral to the House.
        _lendSingle(pair, liquidity);

        // check for dust
        _takeDust(IOption(optionAddress).getUnderlyingTokenAddress());
        _takeDust(IOption(optionAddress).redeemToken());
        _takeWETHDust();

        return (amountA, amountB, liquidity);
    }

    /**
     * @dev    Adds redeemToken liquidity to a redeem<>underlyingToken pair by minting shortOptionTokens with underlyingTokens.
     * @notice Pulls underlying tokens from msg.sender and pushes UNI-V2 liquidity tokens to the "to" address.
     *         underlyingToken -> redeemToken -> UNI-V2.
     * @param optionAddress The address of the optionToken to get the redeemToken to mint then provide liquidity for.
     */
    function _addLiquidity(
        address optionAddress,
        AddLiquidityParams memory params
    )
        internal
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        address underlyingToken =
            IOption(optionAddress).getUnderlyingTokenAddress();
        address shortToken = IOption(optionAddress).redeemToken();
        // Get tokens
        _convertETH(); // ETH - > WETH
        _mintOptions( // Add Long + Short
            optionAddress,
            params.quantityOptions,
            address(this),
            address(this)
        );
        _takeTokens(underlyingToken, params.amountBMax); // Add underlying

        uint256 shortOptions =
            RouterLib.getProportionalShortOptions(
                IOption(optionAddress),
                params.quantityOptions
            );

        address pair = getApprovedPool(optionAddress);

        require(
            shortOptions == IERC20(shortToken).balanceOf(address(this)),
            "Venue: SHORT_IMBALANCE"
        );

        // Add liquidity, get LP tokens
        router.addLiquidity(
            shortToken, // short option
            underlyingToken, // underlying tokens
            IERC20(shortToken).balanceOf(address(this)), // quantity of short options to deposit
            IERC20(underlyingToken).balanceOf(address(this)), // max quantity of underlying tokens to deposit
            shortOptions, // min quantity of short options = short options (adding exact short options)
            params.amountBMin, // min quantity of underlying to deposit
            address(this), // receiving address
            now //params.deadline
        );
    }

    struct RemoveLiquidityParams {
        uint256 liquidity;
        uint256 amountAMin;
        uint256 amountBMin;
        uint256 deadline;
    }

    /**
     * @dev    Combines Uniswap V2 Router "removeLiquidity" function with Primitive "closeOptions" function.
     * @notice Pulls UNI-V2 liquidity shares with shortOption<>underlying token, and optionTokens from msg.sender.
     *         Then closes the longOptionTokens and withdraws underlyingTokens to the "to" address.
     *         Sends underlyingTokens from the burned UNI-V2 liquidity shares to the "to" address.
     *         UNI-V2 -> optionToken -> underlyingToken.
     * @param optionAddress The address of the option that will be closed from burned UNI-V2 liquidity shares.
     * @param liquidity The quantity of liquidity tokens to pull from msg.sender and burn.
     * @param amountAMin The minimum quantity of shortOptionTokens to receive from removing liquidity.
     * @param amountBMin The minimum quantity of underlyingTokens to receive from removing liquidity.
     * @param to The address that receives underlyingTokens from burned UNI-V2, and underlyingTokens from closed options.
     * @param deadline The timestamp to expire a pending transaction.
     */
    function removeShortLiquidityThenCloseOptions(
        address optionAddress,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) internal returns (uint256, uint256) {
        address pair = pool(optionAddress);

        // Get the lp tokens from the House
        _borrowSingle(pair, liquidity);

        // Remove liquidity
        RemoveLiquidityParams memory params =
            RemoveLiquidityParams(liquidity, amountAMin, amountBMin, deadline);
        return _removeLiquidity(optionAddress, params);
    }

    function _removeLiquidity(
        address optionAddress,
        RemoveLiquidityParams memory params
    ) internal returns (uint256, uint256) {
        address pair = getApprovedPool(optionAddress);
        IOption optionToken = IOption(optionAddress);
        address redeemToken = optionToken.redeemToken();
        address underlyingTokenAddress =
            optionToken.getUnderlyingTokenAddress();

        uint256 amountAMin = params.amountAMin;
        uint256 amountBMin = params.amountBMin;

        // When liquidity is added, a depositor gets 2x effective leverage. Calculate withdraw with this in mind.
        uint256 actualLiquidity = params.liquidity;

        // Remove liquidity from Uniswap V2 pool to receive the reserve tokens (shortOptionTokens + UnderlyingTokens).
        (uint256 shortTokensWithdrawn, uint256 underlyingTokensWithdrawn) =
            router.removeLiquidity(
                redeemToken,
                underlyingTokenAddress,
                actualLiquidity,
                amountAMin,
                amountBMin,
                address(this),
                now //params.deadline
            );

        // need to track the long option token balance, and use that to burn as much short options as possible.
        // longOptions = shortOptions / strikeRatio
        uint256 requiredLongOptions =
            RouterLib.getProportionalLongOptions(
                optionToken,
                shortTokensWithdrawn
            );

        // Check the required longOptionTokens balance
        _burnOptions(optionAddress, requiredLongOptions, address(this));

        // Check balances against min Amounts
        uint256 underlyingBalance =
            IERC20(underlyingTokenAddress).balanceOf(address(this));
        uint256 shortBalance = IERC20(redeemToken).balanceOf(address(this));
        require(
            underlyingBalance >= underlyingTokensWithdrawn,
            "Venue: UNDERLYING_AMT"
        );
        require(shortBalance >= shortTokensWithdrawn, "Venue: SHORT_AMT");
        require(
            IERC20(pair).balanceOf(address(this)) >= actualLiquidity,
            "Venue: LIQUIDITY_AMT"
        );

        // Send out tokens in this contract.
        _takeDust(pair);
        _takeDust(underlyingTokenAddress);
        _takeWETHDust();

        return (underlyingBalance, shortBalance);
    }

    // ==== View ====

    /**
     * @dev Gets the name of the contract.
     */
    function getName() external view override returns (string memory) {
        (string memory name, , ) = capitol.getVenueAttributes(address(this));
        return name;
    }

    /**
     * @dev Gets the version of the contract.
     */
    function getVersion() external view override returns (string memory) {
        (, string memory apiVersion, ) =
            capitol.getVenueAttributes(address(this));
        return apiVersion;
    }

    function getIsEndorsed() external view returns (bool) {
        return capitol.getIsEndorsed(address(this));
    }
}
