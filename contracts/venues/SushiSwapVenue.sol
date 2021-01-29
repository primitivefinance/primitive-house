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
import {Venue} from "./Venue.sol";
import {ICapitol} from "../interfaces/ICapitol.sol";
import {IHouse} from "../interfaces/IHouse.sol";
import {IWETH} from "../interfaces/IWETH.sol";
import {SafeMath} from "../libraries/SafeMath.sol";
import {RouterLib} from "../libraries/RouterLib.sol";

import "hardhat/console.sol";

contract SushiSwapVenue is Venue, ISushiSwapVenue {
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
    ) public Venue(weth_, house_) {
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

    function getApprovedPool(address under, address short)
        public
        returns (address)
    {
        address pair = factory.getPair(under, short);
        checkApproved(under, address(router));
        checkApproved(short, address(router));
        checkApproved(pair, address(router));
        checkApproved(under, address(house));
        checkApproved(short, address(house));
        checkApproved(pair, address(house));
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
        {
            uint256[] memory maxAmounts_ = new uint256[](maxAmountsLength);
            maxAmounts_ = maxAmounts;
            uint256[] memory minAmounts_ = new uint256[](minAmountsLength);
            minAmounts_ = minAmounts;
            console.log("entering for loop");
            for (uint256 i = 0; i < optionsLength; i++) {
                address optionAddress = options[i];
                address under =
                    IOption(optionAddress).getUnderlyingTokenAddress();
                (, , , address short) = getVirtualAssets(optionAddress);
                address pair = factory.getPair(under, short);
                uint256 optionsToMint = maxAmounts_[i];
                uint256 underlyingDeposit = maxAmounts_[i + 1];
                uint256 shortOptionsToMint =
                    RouterLib.getProportionalShortOptions(
                        IOption(optionAddress),
                        optionsToMint
                    );
                console.log("checking min amounts");
                require(
                    shortOptionsToMint == minAmounts_[i],
                    "UniswapVenue: SHORT_OPTIONS_INPUT"
                );
                uint256 minUnderlyingDeposit = minAmounts_[i + 1];
                AddLiquidityParams memory params =
                    AddLiquidityParams(
                        optionsToMint,
                        underlyingDeposit,
                        minUnderlyingDeposit,
                        now
                    );
                console.log("adding liquidity internally");
                // Adds liquidity to Uniswap V2 Pair and returns liquidity shares to this contract.
                (, , uint256 liquidity) = _addLiquidity(optionAddress, params);
                // Inputs for lending multiple tokens
                console.log("liquidity added:", liquidity);
                liquidityAmounts[i] = liquidity;
                pairTokens[i] = pair;

                console.log("taking dust");
                // check for dust
                _takeDust(under);
                _takeDust(short);
            }
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
            address under = IOption(optionAddress).getUnderlyingTokenAddress();
            (, , , address short) = getVirtualAssets(optionAddress);
            address pair = factory.getPair(under, short);
            liquidityPools[i] = pair;
        }

        console.log("borrowing multiple");
        _borrowCollateral(liquidityPools, quantities);

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
            console.log("removing liquidity internally");
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
        address option = optionAddress;
        address under = IOption(option).getUnderlyingTokenAddress();
        (, , , address short) = getVirtualAssets(option);
        address pair = getApprovedPool(under, short);
        AddLiquidityParams memory params =
            AddLiquidityParams(
                quantityOptions,
                amountBMax,
                amountBMin,
                deadline
            );
        console.log("adding liquidity");
        // Adds liquidity to Uniswap V2 Pair and returns liquidity shares to this contract.
        (uint256 amountA, uint256 amountB, uint256 liquidity) =
            _addLiquidity(option, params);

        console.log("lending single", liquidity);
        // Add as collateral to the House.
        _lendSingle(pair, liquidity);

        console.log("checking for dust");
        // check for dust
        _takeDust(under);
        _takeDust(short);
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
        (, , , address shortToken) = getVirtualAssets(optionAddress);

        console.log("checking approval for short", shortToken);
        checkApproved(shortToken, address(router));

        console.log("converting eth");
        // Get tokens
        _convertETH(); // ETH - > WETH
        console.log("minting options");
        _mintOptions( // Add Long + Short
            optionAddress,
            params.quantityOptions,
            address(this),
            address(this)
        );
        console.log("taking underlying tokens");
        _takeTokens(underlyingToken, params.amountBMax); // Add underlying

        uint256 shortOptions =
            RouterLib.getProportionalShortOptions(
                IOption(optionAddress),
                params.quantityOptions
            );

        address pair = getApprovedPool(underlyingToken, shortToken);

        require(
            shortOptions == IERC20(shortToken).balanceOf(address(this)),
            "Venue: SHORT_IMBALANCE"
        );

        console.log(
            "calling add liquidity",
            IERC20(shortToken).balanceOf(address(this)),
            IERC20(underlyingToken).balanceOf(address(this))
        );
        // Add liquidity, get LP tokens
        return
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
        address underlyingToken =
            IOption(optionAddress).getUnderlyingTokenAddress();
        (address vOption, , , address shortToken) =
            getVirtualAssets(optionAddress);

        console.log("checking approval for short", shortToken);
        checkApproved(shortToken, address(router));
        IOption optionToken = IOption(optionAddress);

        uint256 amountAMin = params.amountAMin;
        uint256 amountBMin = params.amountBMin;

        // When liquidity is added, a depositor gets 2x effective leverage. Calculate withdraw with this in mind.
        uint256 actualLiquidity = params.liquidity;
        address pair = getApprovedPool(underlyingToken, shortToken);

        console.log("calling remove liquidity to router");
        console.log(IERC20(pair).balanceOf(address(this)), actualLiquidity);

        // Remove liquidity from Uniswap V2 pool to receive the reserve tokens (shortOptionTokens + UnderlyingTokens).
        (uint256 shortTokensWithdrawn, uint256 underlyingTokensWithdrawn) =
            router.removeLiquidity(
                shortToken,
                underlyingToken,
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
        //console.log("taking long options");
        //_takeTokens(vOption, requiredLongOptions); // Add options

        checkApproved(vOption, address(house));
        console.log(
            "burning options",
            IERC20(vOption).balanceOf(address(this))
        );
        // Check the required longOptionTokens balance
        _burnOptions(optionAddress, requiredLongOptions, address(this));

        console.log("checking invariants amts");
        // Check balances against min Amounts
        uint256 underlyingBalance =
            IERC20(underlyingToken).balanceOf(address(this));
        uint256 shortBalance = IERC20(shortToken).balanceOf(address(this));
        console.log("under invariant");
        require(
            underlyingBalance >= underlyingTokensWithdrawn,
            "Venue: UNDERLYING_AMT"
        );

        console.log("taking dust");
        // Send out tokens in this contract.
        _takeDust(pair);
        _takeDust(underlyingToken);
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
