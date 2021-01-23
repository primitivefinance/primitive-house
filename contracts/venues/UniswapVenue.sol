pragma solidity >=0.6.2;

// Open Zeppelin
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {
    ReentrancyGuard
} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

// Primitive
import {
    IUniswapVenue,
    IUniswapV2Router02,
    IUniswapV2Factory,
    IOption,
    IERC20
} from "../interfaces/IUniswapVenue.sol";

// Internal
import {SafeMath} from "../libraries/SafeMath.sol";
import {UniswapVenueLib} from "../libraries/UniswapVenueLib.sol";
import {Venue} from "../Venue.sol";
import {VirtualRouter} from "../VirtualRouter.sol";

contract UniswapVenue is Ownable, Venue, VirtualRouter, ReentrancyGuard {
    using SafeERC20 for IERC20; // Reverts when `transfer` or `transferFrom` erc20 calls don't return proper data
    using SafeMath for uint256; // Reverts on math underflows/overflows

    IUniswapV2Factory public override factory =
        IUniswapV2Factory(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f); // The Uniswap V2 factory contract to get pair addresses from
    IUniswapV2Router02 public override router =
        IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D); // The Uniswap contract used to interact with the protocol

    IWETH public weth;
    IHouse public house;
    ICapitol public capitol;

    event Initialized(address indexed from); // Emmitted on deployment
    event BoughtOptions(
        address indexed from,
        uint256 quantity,
        uint256 premium
    ); // Emmitted on flash opening a long position
    event SoldOptions(address indexed from, uint256 quantity, uint256 payout);
    event WroteOption(address indexed from, uint256 quantity);

    /// @dev Checks the quantity of an operation to make sure its not zero. Fails early.
    modifier nonZero(uint256 quantity) {
        require(quantity > 0, "ERR_ZERO");
        _;
    }

    // ==== Constructor ====

    constructor(
        address weth_,
        address house_,
        address capitol_
    ) public {
        require(address(weth) == address(0x0), "ERR_INITIALIZED");
        weth = IWETH(weth_);
        house = IHouse(house_);
        capitol = ICapitol(capitol_);
        emit Initialized(msg.sender);
    }

    receive() external payable {
        assert(msg.sender == address(weth)); // only accept ETH via fallback from the WETH contract
    }

    // ==== Simple ====
    function pool(address option) external override returns (address) {
        address underlying = IOption(option).getUnderlyingTokenAddress();
        address redeem = IOption(option).redeemToken();
        address pair = factory.getPair(underlying, redeem);
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
    ) public {
        uint256 optionsLength = options.length;
        uint256 maxAmountsLength = maxAmounts.length;
        uint256 minAmountsLength = minAmounts.length;
        // require 2 maxAmounts and minAmounts per option, and ensure maxAmounts = minAmounts lengths.
        require(
            optionsLength == maxAmountsLength.div(2) &&
                maxAmountsLength == minAmountsLength,
            "UniswapVenue: ARRAY_LENGTHS"
        );
        for (uint256 i = 0; i < optionsLength; i++) {
            address optionAddress = options[i];
            uint256 optionsToMint = maxAmounts[i];
            uint256 underlyingDeposit = maxAmounts[i + 1];
            uint256 shortOptionsToMint =
                UniswapVenue.getProportionalShort(optionAddress, optionsToMint);
            require(
                shortOptionsToMint == minAmounts[i],
                "UniswapVenue: SHORT_OPTIONS_INPUT"
            );
            uint256 minUnderlyingToDeposit = minAmounts[i + 1];
            addShortLiquidityWithUnderlying(
                optionAddress,
                optionsToMint,
                underlyingDeposit,
                minUnderlyingDeposit,
                receiver,
                deadline
            );
        }
    }

    function depositLeveraged(
        address optionAddress,
        uint256 quantityOptions,
        uint256 amountBMax,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) public {
        bytes4 selector =
            bytes4(
                keccak256(
                    bytes(
                        "addLiquidity(address,address,uint256,uint256,uint256,uint256,address,uint256)"
                    )
                )
            );

        // encodes the add liquidity function call parameters
        address synthOption = house.syntheticOptions[optionAddress]; // synthetic version of the option
        address redeem = IOption(synthOption).redeemToken(); // synthetic version of the redeem
        address underlying = IOption(optionAddress).getUnderlyingTokenAddress(); // actual underlying
        uint256 total = quantityOptions.add(amountBMax); // the total deposit quantity in underlying tokens
        uint256 outputRedeems = proportionalShort(total); // the synthetic short options minted from total deposit
        bytes memory params =
            abi.encodeWithSelector(
                selector, // function to call in this contract
                redeem,
                underlying,
                outputRedeems,
                amountBMax.mul(2),
                outputRedeems,
                amountBMin.mul(2),
                to,
                deadline
            );

        IUniswapV2Router02 router = router;
        // calls the house to double the position and store the lp tokens as collateral
        // house will call the `params` data to the router.
        house.doublePosition(
            msg.sender,
            optionAddress,
            total,
            address(router),
            params
        );
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
    ) public {
        uint256 optionsLength = options.length;
        uint256 quantitiesLength = quantities.length;
        uint256 minAmountsLength = minAmounts.length;
        // require 2 minAmounts per option, and ensure quantities = options lengths.
        require(
            optionsLength == quantitiesLength &&
                quantitiesLength == minAmountsLength.div(2),
            "UniswapVenue: ARRAY_LENGTHS"
        );
        for (uint256 i = 0; i < optionsLength; i++) {
            address optionAddress = options[i];
            uint256 liquidityToBurn = quantities[i];
            uint256 minimumShortOptions = minAmounts[i];
            uint256 minimumUnderlyingTokens = minAmounts[i + 1];
            removeShortLiquidityThenCloseOptions(
                optionAddress,
                liquidityToBurn,
                minimumShortOptions,
                minimumUnderlyingTokens,
                receiver,
                deadline
            );
        }
    }

    function withdrawDouble(
        address[] memory options,
        uint256[] memory quantities,
        uint256[] memory minAmounts,
        address receiver,
        uint256 deadline
    ) public {
        bytes4 selector =
            bytes4(
                keccak256(
                    bytes(
                        "removeLiquidity(address,address,uint256,uint256,uint256,address,uint256)"
                    )
                )
            );

        // encodes the add liquidity function call parameters
        address synthOption = house.syntheticOptions[optionAddress]; // synthetic version of the option
        address redeem = IOption(synthOption).redeemToken(); // synthetic version of the redeem
        address underlying = IOption(optionAddress).getUnderlyingTokenAddress(); // actual underlying
        bytes memory params =
            abi.encodeWithSelector(
                selector, // function to call in this contract
                redeem,
                underlying,
                liquidity,
                amountAMin,
                amountBMin,
                to,
                deadline
            );

        IUniswapV2Router02 router = router;
        // calls the house to double the position and store the lp tokens as collateral
        // house will call the `params` data to the router.
        house.doubleUnwind(
            msg.sender,
            optionAddress,
            liquidity,
            address(router),
            params
        );
    }

    // ==== Swap Operations ====

    /**
     * @dev    Write options by minting option tokens and selling the long option tokens for premium.
     * @notice IMPORTANT: if `minPayout` is 0, this function can cost the caller `underlyingToken`s.
     * @param options The option contract to underwrite.
     * @param quantities The quantity of option tokens to write and equally, the quantity of underlyings to deposit.
     * @param minAmounts The minimum amount of underlyingTokens to receive from selling long option tokens.
     */
    function writeOptions(
        IOption[] memory options,
        uint256[] memory quantities,
        uint256[] memory minAmounts
    ) external returns (bool) {
        uint256 optionsLength = options.length;
        uint256 quantitiesLength = quantities.length;
        uint256 minAmountsLength = minAmounts.length;
        require(
            optionsLength == quantitiesLength &&
                quantitiesLength == minAmountsLength,
            "UniswapVenue: ARRAY_LENGTHS"
        );

        bool success;
        for (uint256 i = 0; i < optionsLength; i++) {
            IOption optionToken = options[i];
            uint256 writeQuantity = quantities[i];
            uint256 minPayout = minAmounts[i];
            // Pulls underlyingTokens from `msg.sender` using `transferFrom`. Mints option tokens to `msg.sender`.
            (, uint256 outputRedeems) =
                safeMint(optionToken, writeQuantity, msg.sender);

            // Sell the long option tokens for underlyingToken premium.
            success = closeFlashLong(optionToken, outputRedeems, minPayout);
            require(success, "ERR_FLASH_CLOSE");
            emit WroteOption(msg.sender, writeQuantity);
        }
        return success;
    }

    // need to work on this function to make sure it works.
    /**
     * @dev    Write WETH options using ETH and sell them for premium.
     * @notice IMPORTANT: if `minPayout` is 0, this function can cost the caller `underlyingToken`s.
     * @param optionToken The option contract to underwrite.
     * @param minPayout The minimum amount of underlyingTokens to receive from selling long option tokens.
     */
    /* function mintETHOptionsThenFlashCloseLongForETH(
        IOption optionToken,
        uint256 minPayout
    ) external payable returns (bool) {
        require(
            optionToken.getUnderlyingTokenAddress() == address(weth),
            "PrimitiveV1: NOT_WETH"
        );
        // Mints WETH options uses an ether balance `msg.value`.
        (, uint256 outputRedeems) = safeMintWithETH(optionToken, msg.sender);

        // Sell the long option tokens for underlyingToken premium.
        bool success =
            closeFlashLongForETH(optionToken, outputRedeems, minPayout);
        require(success, "ERR_FLASH_CLOSE");
        emit WroteOption(msg.sender, msg.value);
        return success;
    } */

    /**
     * @dev    Opens a longOptionToken position by minting long + short tokens, then selling the short tokens.
     * @notice IMPORTANT: amountOutMin parameter is the price to swap shortOptionTokens to underlyingTokens.
     *         IMPORTANT: If the ratio between shortOptionTokens and underlyingTokens is 1:1, then only the swap fee (0.30%) has to be paid.
     * @param options The option address.
     * @param quantities The quantity of longOptionTokens to purchase.
     * @param maxAmounts The maximum quantity of underlyingTokens to pay for the optionTokens.
     */
    function swapFromUnderlyingToOptions(
        IOption[] memory options,
        uint256[] memory quantities,
        uint256[] memory maxAmounts
    ) public override nonReentrant returns (bool) {
        bytes4 selector =
            bytes4(
                keccak256(
                    bytes(
                        "flashMintShortOptionsThenSwap(address,uint256,uint256,address)"
                    )
                )
            );

        uint256 optionsLength = options.length;
        uint256 quantitiesLength = quantities.length;
        uint256 maxAmountsLength = maxAmounts.length;
        require(
            optionsLength == quantitiesLength &&
                quantitiesLength == maxAmountsLength,
            "UniswapVenue: ARRAY_LENGTHS"
        );
        for (uint256 i = 0; i < optionsLength; i++) {
            IOption optionToken = options[i];
            uint256 amountOptions = quantities[i];
            uint256 maxPremium = maxAmounts[i];
            bytes memory params =
                abi.encodeWithSelector(
                    selector, // function to call in this contract
                    optionToken, // option token to mint with flash loaned tokens
                    amountOptions, // quantity of underlyingTokens from flash loan to use to mint options
                    maxPremium, // total price paid (in underlyingTokens) for selling shortOptionTokens
                    msg.sender // address to pull the remainder loan amount to pay, and send longOptionTokens to.
                );
            _swapForUnderlying(optionToken, amountOptions, params);
        }
        return true;
    }

    /**
     * @dev    Opens a longOptionToken position by minting long + short tokens, then selling the short tokens.
     * @notice IMPORTANT: amountOutMin parameter is the price to swap shortOptionTokens to underlyingTokens.
     *         IMPORTANT: If the ratio between shortOptionTokens and underlyingTokens is 1:1, then only the swap fee (0.30%) has to be paid.
     * @param options The option address.
     * @param quantities The quantity of longOptionTokens to purchase.
     * @param maxAmounts The maximum quantity of underlyingTokens to pay for the optionTokens.
     */
    function swapFromETHToOptions(
        IOption[] memory options,
        uint256[] memory quantities,
        uint256[] memory maxAmounts
    ) external payable nonZero(msg.value) returns (bool) {
        bytes4 selector =
            bytes4(
                keccak256(
                    bytes(
                        "flashMintShortOptionsThenSwapWithETH(address,uint256,uint256,address)"
                    )
                )
            );

        uint256 totalMaxPremium;
        for (uint256 i = 0; i < optionsLength; i++) {
            totalMaxPremium = totalMaxPremium.add(maxAmounts[i]);
        }
        require(
            totalMaxPremium == msg.value,
            "UniswapVenue: TOTAL_MAX_PREMIUM"
        ); // must assert because cannot check in callback

        uint256 optionsLength = options.length;
        uint256 quantitiesLength = quantities.length;
        uint256 maxAmountsLength = maxAmounts.length;
        require(
            optionsLength == quantitiesLength &&
                quantitiesLength == maxAmountsLength,
            "UniswapVenue: ARRAY_LENGTHS"
        );
        for (uint256 i = 0; i < optionsLength; i++) {
            IOption optionToken = options[i];
            uint256 amountOptions = quantities[i];
            uint256 maxPremium = maxAmounts[i];
            bytes memory params =
                abi.encodeWithSelector(
                    selector, // function to call in this contract
                    optionToken, // option token to mint with flash loaned tokens
                    amountOptions, // quantity of underlyingTokens from flash loan to use to mint options
                    maxPremium, // total price paid (in underlyingTokens) for selling shortOptionTokens
                    msg.sender // address to pull the remainder loan amount to pay, and send longOptionTokens to.
                );
            _swapForUnderlying(optionToken, amountOptions, params);
        }
        return true;
    }

    /**
     * @dev    Closes a longOptionToken position by flash swapping in redeemTokens,
     *         closing the option, and paying back in underlyingTokens.
     * @notice IMPORTANT: If minPayout is 0, this function will cost the caller to close the option, for no gain.
     * @param options The address of the longOptionTokens to close.
     * @param quantities The quantity of redeemTokens to borrow to close the options.
     * @param minAmounts The minimum payout of underlyingTokens sent out to the user.
     */
    function swapFromOptionsToUnderlying(
        IOption[] memory options,
        uint256[] memory quantities,
        uint256[] memory minAmounts
    ) public override nonReentrant returns (bool) {
        bytes4 selector =
            bytes4(
                keccak256(
                    bytes(
                        "flashCloseLongOptionsThenSwap(address,uint256,uint256,address)"
                    )
                )
            );

        uint256 optionsLength = options.length;
        uint256 quantitiesLength = quantities.length;
        uint256 minAmountsLength = minAmounts.length;
        require(
            optionsLength == quantitiesLength &&
                quantitiesLength == minAmountsLength,
            "UniswapVenue: ARRAY_LENGTHS"
        );
        for (uint256 i = 0; i < optionsLength; i++) {
            IOption optionToken = options[i];
            uint256 amountRedeems = quantities[i];
            uint256 minPayout = minAmounts[i];
            bytes memory params =
                abi.encodeWithSelector(
                    selector, // function to call in this contract
                    optionToken, // option token to close with flash loaned redeemTokens
                    amountRedeems, // quantity of redeemTokens from flash loan to use to close options
                    minPayout, // total remaining underlyingTokens after flash loan is paid
                    msg.sender // address to send payout of underlyingTokens to. Will pull underlyingTokens if negative payout and minPayout <= 0.
                );
            _swapForRedeem(optionToken, amountRedeems, params);
        }
        return true;
    }

    /**
     * @dev    Closes a longOptionToken position by flash swapping in redeemTokens,
     *         closing the option, and paying back in underlyingTokens.
     * @notice IMPORTANT: If minPayout is 0, this function will cost the caller to close the option, for no gain.
     * @param options The address of the longOptionTokens to close.
     * @param quantities The quantity of redeemTokens to borrow to close the options.
     * @param minAmounts The minimum payout of underlyingTokens sent out to the user.
     */
    function swapFromOptionsToETH(
        IOption[] calldata options,
        uint256[] calldata quantities,
        uint256[] calldata minAmounts
    ) public nonReentrant returns (bool) {
        bytes4 selector =
            bytes4(
                keccak256(
                    bytes(
                        "flashCloseLongOptionsThenSwapForETH(address,uint256,uint256,address)"
                    )
                )
            );
        uint256 optionsLength = options.length;
        uint256 quantitiesLength = quantities.length;
        uint256 minAmountsLength = minAmounts.length;
        require(
            optionsLength == quantitiesLength &&
                quantitiesLength == minAmountsLength,
            "UniswapVenue: ARRAY_LENGTHS"
        );
        for (uint256 i = 0; i < optionsLength; i++) {
            IOption optionToken = options[i];
            uint256 amountRedeems = quantities[i];
            uint256 minPayout = minAmounts[i];
            bytes memory params =
                abi.encodeWithSelector(
                    selector, // function to call in this contract
                    optionToken, // option token to close with flash loaned redeemTokens
                    amountRedeems, // quantity of redeemTokens from flash loan to use to close options
                    minPayout, // total remaining underlyingTokens after flash loan is paid
                    msg.sender // address to send payout of underlyingTokens to. Will pull underlyingTokens if negative payout and minPayout <= 0.
                );
            _swapForRedeem(optionToken, amountRedeems, params);
        }
        return true;
    }

    function _swapForUnderlying(
        IOption optionToken,
        uint256 amountOptions,
        bytes memory params
    ) internal {
        address redeemToken = optionToken.redeemToken();
        address underlyingToken = optionToken.getUnderlyingTokenAddress();
        IUniswapV2Pair pair =
            IUniswapV2Pair(factory.getPair(redeemToken, underlyingToken));

        // Receives 0 quoteTokens and `amountOptions` of underlyingTokens to `this` contract address.
        // Then executes `flashMintShortOptionsThenSwap`.
        uint256 amount0Out =
            pair.token0() == underlyingToken ? amountOptions : 0;
        uint256 amount1Out =
            pair.token0() == underlyingToken ? 0 : amountOptions;

        // Borrow the amountOptions quantity of underlyingTokens and execute the callback function using params.
        pair.swap(amount0Out, amount1Out, address(this), params);
    }

    function _swapForRedeem(
        IOption optionToken,
        uint256 amountRedeems,
        bytes memory params
    ) internal {
        address redeemToken = optionToken.redeemToken();
        address underlyingToken = optionToken.getUnderlyingTokenAddress();
        IUniswapV2Pair pair =
            IUniswapV2Pair(factory.getPair(redeemToken, underlyingToken));

        // Build the path to get the appropriate reserves to borrow from, and then pay back.
        // We are borrowing from reserve1 then paying it back mostly in reserve0.
        // Borrowing redeemTokens, paying back in underlyingTokens (normal swap).
        // Pay any remainder in underlyingTokens.

        // Receives 0 underlyingTokens and `amountRedeems` of redeemTokens to `this` contract address.
        // Then executes `flashCloseLongOptionsThenSwap`.
        uint256 amount0Out = pair.token0() == redeemToken ? amountRedeems : 0;
        uint256 amount1Out = pair.token0() == redeemToken ? 0 : amountRedeems;

        // Borrow the amountRedeems quantity of redeemTokens and execute the callback function using params.
        pair.swap(amount0Out, amount1Out, address(this), params);
    }

    // ==== Liquidity Functions ====

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
        public
        override
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        uint256 amountA;
        uint256 amountB;
        uint256 liquidity;
        // Pulls underlyingTokens from msg.sender to this contract.
        // Pushes underlyingTokens to option contract and mints option + redeem tokens to this contract.
        // Warning: calls into msg.sender using `safeTransferFrom`. Msg.sender is not trusted.
        (, uint256 outputRedeems) =
            safeMint(IOption(optionAddress), quantityOptions, address(this));
        // Send longOptionTokens from minting option operation to msg.sender.
        IERC20(optionAddress).safeTransfer(msg.sender, quantityOptions);

        {
            // scope for adding exact liquidity, avoids stack too deep errors
            IOption optionToken = IOption(optionAddress);
            address underlyingToken = optionToken.getUnderlyingTokenAddress();
            uint256 outputRedeems_ = outputRedeems;
            uint256 amountBMax_ = amountBMax;
            uint256 amountBMin_ = amountBMin;
            address to_ = to;
            uint256 deadline_ = deadline;
            // Pull `tokenB` from msg.sender to add to Uniswap V2 Pair.
            // Warning: calls into msg.sender using `safeTransferFrom`. Msg.sender is not trusted.
            IERC20(underlyingToken).safeTransferFrom(
                msg.sender,
                address(this),
                amountBMax_
            );
            // Approves Uniswap V2 Pair pull tokens from this contract.
            IERC20(optionToken.redeemToken()).approve(
                address(router),
                uint256(-1)
            );
            IERC20(underlyingToken).approve(address(router), uint256(-1));

            // Adds liquidity to Uniswap V2 Pair and returns liquidity shares to the "to" address.
            (amountA, amountB, liquidity) = router.addLiquidity(
                optionToken.redeemToken(),
                underlyingToken,
                outputRedeems_,
                amountBMax_,
                outputRedeems_,
                amountBMin_,
                to_,
                deadline_
            );
            // check for exact liquidity provided
            assert(amountA == outputRedeems);

            uint256 remainder =
                amountBMax_ > amountB ? amountBMax_.sub(amountB) : 0;
            if (remainder > 0) {
                IERC20(underlyingToken).safeTransfer(msg.sender, remainder);
            }
        }
        return (amountA, amountB, liquidity);
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
    function addShortLiquidityWithETH(
        address optionAddress,
        uint256 quantityOptions,
        uint256 amountBMax,
        uint256 amountBMin,
        address to,
        uint256 deadline
    )
        public
        payable
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        require(
            quantityOptions.add(amountBMax) >= msg.value,
            "ERR_NOT_ENOUGH_ETH"
        );

        uint256 amountA;
        uint256 amountB;
        uint256 liquidity;
        // Pulls underlyingTokens from msg.sender to this contract.
        // Pushes underlyingTokens to option contract and mints option + redeem tokens to this contract.
        // Warning: calls into msg.sender using `safeTransferFrom`. Msg.sender is not trusted.
        // Deposit the ethers received from msg.value into the WETH contract.
        weth.deposit.value(quantityOptions)();
        // Send WETH to option. Remainder ETH will be pulled from Uniswap V2 Router for adding liquidity.
        weth.transfer(optionAddress, quantityOptions);
        // Mint options
        (, uint256 outputRedeems) =
            IOption(optionAddress).mintOptions(address(this));
        // Send longOptionTokens from minting option operation to msg.sender.
        IERC20(optionAddress).safeTransfer(msg.sender, quantityOptions);

        {
            // scope for adding exact liquidity, avoids stack too deep errors
            IOption optionToken = IOption(optionAddress);
            address underlyingToken = optionToken.getUnderlyingTokenAddress();
            uint256 outputRedeems_ = outputRedeems;
            uint256 amountBMax_ = amountBMax;
            uint256 amountBMin_ = amountBMin;
            address to_ = to;
            uint256 deadline_ = deadline;
            // Pull `tokenB` from msg.sender to add to Uniswap V2 Pair.
            // Warning: calls into msg.sender using `safeTransferFrom`. Msg.sender is not trusted.
            /* IERC20(underlyingToken).safeTransferFrom(
                msg.sender,
                address(this),
                amountBMax_
            ); */
            // Approves Uniswap V2 Pair pull tokens from this contract.
            IERC20(optionToken.redeemToken()).approve(
                address(router),
                uint256(-1)
            );
            IERC20(underlyingToken).approve(address(router), uint256(-1));

            // Adds liquidity to Uniswap V2 Pair and returns liquidity shares to the "to" address.
            (amountA, amountB, liquidity) = router.addLiquidityETH.value(
                amountBMax_
            )(
                optionToken.redeemToken(),
                outputRedeems_,
                outputRedeems_,
                amountBMin_,
                to_,
                deadline_
            );
            // check for exact liquidity provided
            assert(amountA == outputRedeems);

            uint256 remainder =
                amountBMax_ > amountB ? amountBMax_.sub(amountB) : 0;
            if (remainder > 0) {
                // Send ether.
                (bool success, ) = msg.sender.call.value(remainder)("");
                // Revert is call is unsuccessful.
                require(success, "ERR_SENDING_ETHER");
            }
        }
        return (amountA, amountB, liquidity);
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
    ) public override nonReentrant returns (uint256, uint256) {
        IOption optionToken = IOption(optionAddress);
        address redeemToken = optionToken.redeemToken();
        address underlyingTokenAddress =
            optionToken.getUnderlyingTokenAddress();

        // Check the short option tokens before and after, there could be dust.
        uint256 redeemBalance = IERC20(redeemToken).balanceOf(address(this));

        // Remove liquidity by burning lp tokens from msg.sender, withdraw tokens to this contract.
        // Notice: the `to` address is not passed into this function, because address(this) receives the withrawn tokens.
        // Gets the Uniswap V2 Pair address for shortOptionToken (redeem) and underlyingTokens.
        // Transfers the LP tokens of the pair to this contract.

        uint256 liquidity_ = liquidity;
        uint256 amountAMin_ = amountAMin;
        uint256 amountBMin_ = amountBMin;
        uint256 deadline_ = deadline;
        address to_ = to;
        // Warning: public call to a non-trusted address `msg.sender`.
        IERC20(factory.getPair(redeemToken, underlyingTokenAddress))
            .safeTransferFrom(msg.sender, address(this), liquidity_);
        IERC20(factory.getPair(redeemToken, underlyingTokenAddress)).approve(
            address(router),
            uint256(-1)
        );

        // Remove liquidity from Uniswap V2 pool to receive the reserve tokens (shortOptionTokens + UnderlyingTokens).
        (uint256 shortTokensWithdrawn, uint256 underlyingTokensWithdrawn) =
            router.removeLiquidity(
                redeemToken,
                underlyingTokenAddress,
                liquidity_,
                amountAMin_,
                amountBMin_,
                address(this),
                deadline_
            );

        // Burn option and redeem tokens from this contract then send underlyingTokens to the `to` address.
        // Calculate equivalent quantity of redeem (short option) tokens to close the long option position.
        // Close longOptionTokens using the redeemToken balance of this contract.
        IERC20(optionToken.redeemToken()).safeTransfer(
            address(optionToken),
            shortTokensWithdrawn
        );

        // longOptions = shortOptions / strikeRatio
        uint256 requiredLongOptions =
            UniswapVenueLib.getProportionalLongOptions(
                optionToken,
                shortTokensWithdrawn
            );

        // Pull the required longOptionTokens from `msg.sender` to this contract.
        IERC20(address(optionToken)).safeTransferFrom(
            msg.sender,
            address(optionToken),
            requiredLongOptions
        );

        // Trader pulls option and redeem tokens from this contract and sends them to the option contract.
        // Option and redeem tokens are then burned to release underlyingTokens.
        // UnderlyingTokens are sent to the "receiver" address.
        (, , uint256 underlyingTokensFromClosedOptions) =
            optionToken.closeOptions(to_);

        // After the options were closed, calculate the dust by checking after balance against the before balance.
        redeemBalance = IERC20(redeemToken).balanceOf(address(this)).sub(
            redeemBalance
        );

        // If there is dust, send it out
        if (redeemBalance > 0) {
            IERC20(redeemToken).safeTransfer(to_, redeemBalance);
        }

        // Send the UnderlyingTokens received from burning liquidity shares to the "to" address.
        IERC20(underlyingTokenAddress).safeTransfer(
            to_,
            underlyingTokensWithdrawn
        );
        return (
            underlyingTokensWithdrawn.add(underlyingTokensFromClosedOptions),
            redeemBalance
        );
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
    function removeShortLiquidityThenCloseOptionsForETH(
        address optionAddress,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) public returns (uint256, uint256) {
        (uint256 totalUnderlying, uint256 totalRedeem) =
            removeShortLiquidityThenCloseOptions(
                optionAddress,
                liquidity,
                amountAMin,
                amountBMin,
                address(this),
                deadline
            );
        UniswapVenueLib.safeTransferWETHToETH(weth, to, totalUnderlying);
        IERC20(IOption(optionAddress).redeemToken()).safeTransfer(
            to,
            totalRedeem
        );
        return (totalUnderlying, totalRedeem);
    }

    function removeShortLiquidityThenCloseOptionsForETHWithPermit(
        address optionAddress,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256, uint256) {
        IOption optionToken = IOption(optionAddress);
        uint256 liquidity_ = liquidity;
        uint256 deadline_ = deadline;
        address to_ = to;
        {
            uint8 v_ = v;
            bytes32 r_ = r;
            bytes32 s_ = s;
            address redeemToken = optionToken.redeemToken();
            address underlyingTokenAddress =
                optionToken.getUnderlyingTokenAddress();
            IUniswapV2Pair(factory.getPair(redeemToken, underlyingTokenAddress))
                .permit(
                msg.sender,
                address(this),
                uint256(-1),
                deadline_,
                v_,
                r_,
                s_
            );
        }
        uint256 amountAMin_ = amountAMin;
        uint256 amountBMin_ = amountBMin;
        return
            removeShortLiquidityThenCloseOptionsForETH(
                address(optionToken),
                liquidity_,
                amountAMin_,
                amountBMin_,
                to_,
                deadline_
            );
    }

    function removeShortLiquidityThenCloseOptionsWithPermit(
        address optionAddress,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256, uint256) {
        IOption optionToken = IOption(optionAddress);
        uint256 liquidity_ = liquidity;
        uint256 deadline_ = deadline;
        uint256 amountAMin_ = amountAMin;
        uint256 amountBMin_ = amountBMin;
        address to_ = to;
        {
            uint8 v_ = v;
            bytes32 r_ = r;
            bytes32 s_ = s;
            address redeemToken = optionToken.redeemToken();
            address underlyingTokenAddress =
                optionToken.getUnderlyingTokenAddress();
            IUniswapV2Pair(factory.getPair(redeemToken, underlyingTokenAddress))
                .permit(
                msg.sender,
                address(this),
                uint256(-1),
                deadline_,
                v_,
                r_,
                s_
            );
        }
        return
            removeShortLiquidityThenCloseOptions(
                address(optionToken),
                liquidity_,
                amountAMin_,
                amountBMin_,
                to_,
                deadline_
            );
    }

    // ==== Flash Functions ====

    function _flashMintShortOptionsThenSwap(
        address optionAddress,
        uint256 flashLoanQuantity,
        address to
    ) internal returns (uint256) {
        // IMPORTANT: Assume this contract has already received `flashLoanQuantity` of underlyingTokens.
        address underlyingToken =
            IOption(optionAddress).getUnderlyingTokenAddress();
        address redeemToken = IOption(optionAddress).redeemToken();
        address pairAddress = factory.getPair(underlyingToken, redeemToken);

        // Mint longOptionTokens using the underlyingTokens received from UniswapV2 flash swap to this contract.
        // Send underlyingTokens from this contract to the optionToken contract, then call mintOptions.
        IERC20(underlyingToken).safeTransfer(optionAddress, flashLoanQuantity);
        // Mint longOptionTokens using the underlyingTokens received from UniswapV2 flash swap to this contract.
        // Send underlyingTokens from this contract to the optionToken contract, then call mintOptions.
        (uint256 mintedOptions, uint256 mintedRedeems) =
            IOption(optionAddress).mintOptions(address(this));

        // The loanRemainder will be the amount of underlyingTokens that are needed from the original
        // transaction caller in order to pay the flash swap.
        // IMPORTANT: THIS IS EFFECTIVELY THE PREMIUM PAID IN UNDERLYINGTOKENS TO PURCHASE THE OPTIONTOKEN.
        uint256 loanRemainder;

        // Economically, negativePremiumPaymentInRedeems value should always be 0.
        // In the case that we minted more redeemTokens than are needed to pay back the flash swap,
        // (short -> underlying is a positive trade), there is an effective negative premium.
        // In that case, this function will send out `negativePremiumAmount` of redeemTokens to the original caller.
        // This means the user gets to keep the extra redeemTokens for free.
        // Negative premium amount is the opposite difference of the loan remainder: (paid - flash loan amount)
        uint256 negativePremiumPaymentInRedeems;
        (loanRemainder, negativePremiumPaymentInRedeems) = getOpenPremium(
            IOption(optionAddress),
            flashLoanQuantity
        );

        // In the case that more redeemTokens were minted than need to be sent back as payment,
        // calculate the new mintedRedeems value to send to the pair
        // (don't send all the minted redeemTokens).
        if (negativePremiumPaymentInRedeems > 0) {
            mintedRedeems = mintedRedeems.sub(negativePremiumPaymentInRedeems);
        }

        // In most cases, all of the minted redeemTokens will be sent to the pair as payment for the flash swap.
        if (mintedRedeems > 0) {
            IERC20(redeemToken).safeTransfer(pairAddress, mintedRedeems);
        }

        // If negativePremiumAmount is non-zero and non-negative, send redeemTokens to the `to` address.
        if (negativePremiumPaymentInRedeems > 0) {
            IERC20(redeemToken).safeTransfer(
                to,
                negativePremiumPaymentInRedeems
            );
        }

        // Send minted longOptionTokens (option) to the original msg.sender.
        IERC20(optionAddress).safeTransfer(to, flashLoanQuantity);
        emit BoughtOptions(msg.sender, flashLoanQuantity, loanRemainder);
        return loanRemainder;
    }

    /**
     * @dev    Receives underlyingTokens from a UniswapV2Pair.swap() call from a pair with
     *         shortOptionTokens and underlyingTokens.
     *         Uses underlyingTokens to mint long (option) + short (redeem) tokens.
     *         Sends longOptionTokens to msg.sender, and pays back the UniswapV2Pair with shortOptionTokens,
     *         AND any remainder quantity of underlyingTokens (paid by msg.sender).
     * @notice If the first address in the path is not the shortOptionToken address, the tx will fail.
     *         IMPORTANT: UniswapV2 adds a fee of 0.301% to the option premium cost.
     * @param optionAddress The address of the Option contract.
     * @param flashLoanQuantity The quantity of options to mint using borrowed underlyingTokens.
     * @param maxPremium The maximum quantity of underlyingTokens to pay for the optionTokens.
     * @param to The address to send the shortOptionToken proceeds and longOptionTokens to.
     * @return success bool Whether the transaction was successful or not.
     */
    function flashMintShortOptionsThenSwap(
        address optionAddress,
        uint256 flashLoanQuantity,
        uint256 maxPremium,
        address to
    ) public payable override returns (uint256, uint256) {
        require(msg.sender == address(this), "ERR_NOT_SELF");
        require(to != address(0x0), "ERR_TO_ADDRESS_ZERO");
        require(to != msg.sender, "ERR_TO_MSG_SENDER");
        // IMPORTANT: Assume this contract has already received `flashLoanQuantity` of underlyingTokens.
        address underlyingToken =
            IOption(optionAddress).getUnderlyingTokenAddress();
        address redeemToken = IOption(optionAddress).redeemToken();
        address pairAddress = factory.getPair(underlyingToken, redeemToken);

        uint256 loanRemainder =
            _flashMintShortOptionsThenSwap(
                optionAddress,
                flashLoanQuantity,
                to
            );

        // If loanRemainder is non-zero and non-negative (most cases), send underlyingTokens to the pair as payment (premium).
        if (loanRemainder > 0) {
            address pairAddress_ = pairAddress;
            // Pull underlyingTokens from the original msg.sender to pay the remainder of the flash swap.
            require(maxPremium >= loanRemainder, "ERR_PREMIUM_OVER_MAX"); // check for users to not pay over their max desired value.
            IERC20(underlyingToken).safeTransferFrom(
                to,
                pairAddress,
                loanRemainder
            );
        }
        return (flashLoanQuantity, loanRemainder);
    }

    /**
     * @dev    Receives underlyingTokens from a UniswapV2Pair.swap() call from a pair with
     *         shortOptionTokens and underlyingTokens.
     *         Uses underlyingTokens to mint long (option) + short (redeem) tokens.
     *         Sends longOptionTokens to msg.sender, and pays back the UniswapV2Pair with shortOptionTokens,
     *         AND any remainder quantity of underlyingTokens (paid by msg.sender).
     * @notice If the first address in the path is not the shortOptionToken address, the tx will fail.
     *         IMPORTANT: UniswapV2 adds a fee of 0.301% to the option premium cost.
     * @param optionAddress The address of the Option contract.
     * @param flashLoanQuantity The quantity of options to mint using borrowed underlyingTokens.
     * @param maxPremium The maximum quantity of underlyingTokens to pay for the optionTokens.
     * @param to The address to send the shortOptionToken proceeds and longOptionTokens to.
     * @return success bool Whether the transaction was successful or not.
     */
    function flashMintShortOptionsThenSwapWithETH(
        address optionAddress,
        uint256 flashLoanQuantity,
        uint256 maxPremium,
        address to
    ) public payable returns (uint256, uint256) {
        require(msg.sender == address(this), "ERR_NOT_SELF");
        require(to != address(0x0), "ERR_TO_ADDRESS_ZERO");
        require(to != msg.sender, "ERR_TO_MSG_SENDER");
        // IMPORTANT: Assume this contract has already received `flashLoanQuantity` of underlyingTokens.
        address underlyingToken =
            IOption(optionAddress).getUnderlyingTokenAddress();
        address redeemToken = IOption(optionAddress).redeemToken();
        address pairAddress = factory.getPair(underlyingToken, redeemToken);

        uint256 loanRemainder =
            _flashMintShortOptionsThenSwap(
                optionAddress,
                flashLoanQuantity,
                to
            );
        // If loanRemainder is non-zero and non-negative (most cases), send underlyingTokens to the pair as payment (premium).
        if (loanRemainder > 0) {
            address pairAddress_ = pairAddress;
            // Pull underlyingTokens from the original msg.sender to pay the remainder of the flash swap.
            require(maxPremium >= loanRemainder, "ERR_PREMIUM_OVER_MAX"); // check for users to not pay over their max desired value.
            //_payPremiumInETH(pairAddress, loanRemainder);
            weth.deposit.value(loanRemainder)();
            // Transfer weth to pair to pay for premium
            IERC20(address(weth)).safeTransfer(pairAddress, loanRemainder);
            if (maxPremium > loanRemainder) {
                // Send ether.
                (bool success, ) =
                    to.call.value(maxPremium.sub(loanRemainder))("");
                // Revert is call is unsuccessful.
                require(success, "ERR_SENDING_ETHER");
            }
        }

        return (flashLoanQuantity, loanRemainder);
    }

    function _flashCloseLongOptionsThenSwap(
        address optionAddress,
        uint256 flashLoanQuantity,
        uint256 minPayout,
        address to
    ) internal returns (uint256, uint256) {
        address underlyingToken =
            IOption(optionAddress).getUnderlyingTokenAddress();
        address redeemToken = IOption(optionAddress).redeemToken();
        address pairAddress = factory.getPair(underlyingToken, redeemToken);

        // IMPORTANT: Assume this contract has already received `flashLoanQuantity` of redeemTokens.
        // We are flash swapping from an underlying <> shortOptionToken pair,
        // paying back a portion using underlyingTokens received from closing options.
        // In the flash open, we did redeemTokens to underlyingTokens.
        // In the flash close, we are doing underlyingTokens to redeemTokens and keeping the remainder.

        // Close longOptionTokens using the redeemToken balance of this contract.
        IERC20(redeemToken).safeTransfer(optionAddress, flashLoanQuantity);
        uint256 requiredLongOptions =
            UniswapVenueLib.getProportionalLongOptions(
                IOption(optionAddress),
                flashLoanQuantity
            );

        // Send out the required amount of options from the `to` address.
        // WARNING: CALLS TO UNTRUSTED ADDRESS.
        if (IOption(optionAddress).getExpiryTime() >= now)
            IERC20(optionAddress).safeTransferFrom(
                to,
                optionAddress,
                requiredLongOptions
            );

        // Close the options.
        // Quantity of underlyingTokens this contract receives from burning option + redeem tokens.
        (, , uint256 outputUnderlyings) =
            IOption(optionAddress).closeOptions(address(this));

        // Loan Remainder is the cost to pay out, should be 0 in most cases.
        // Underlying Payout is the `premium` that the original caller receives in underlyingTokens.
        // It's the remainder of underlyingTokens after the pair has been paid back underlyingTokens for the
        // flash swapped shortOptionTokens.
        (uint256 underlyingPayout, uint256 loanRemainder) =
            getClosePremium(IOption(optionAddress), flashLoanQuantity);

        // In most cases there will be an underlying payout, which is subtracted from the outputUnderlyings.
        if (underlyingPayout > 0) {
            outputUnderlyings = outputUnderlyings.sub(underlyingPayout);
        }

        // Pay back the pair in underlyingTokens.
        if (outputUnderlyings > 0) {
            IERC20(underlyingToken).safeTransfer(
                pairAddress,
                outputUnderlyings
            );
        }

        // If loanRemainder is non-zero and non-negative, send underlyingTokens to the pair as payment (premium).
        if (loanRemainder > 0) {
            // Pull underlyingTokens from the original msg.sender to pay the remainder of the flash swap.
            // Revert if the minPayout is less than or equal to the underlyingPayment of 0.
            // There is 0 underlyingPayment in the case that loanRemainder > 0.
            // This code branch can be successful by setting `minPayout` to 0.
            // This means the user is willing to pay to close the position.
            require(minPayout <= underlyingPayout, "ERR_NEGATIVE_PAYOUT");
            IERC20(underlyingToken).safeTransferFrom(
                to,
                pairAddress,
                loanRemainder
            );
        }

        emit SoldOptions(msg.sender, outputUnderlyings, underlyingPayout);
        return (outputUnderlyings, underlyingPayout);
    }

    /**
     * @dev    Sends shortOptionTokens to msg.sender, and pays back the UniswapV2Pair in underlyingTokens.
     * @notice IMPORTANT: If minPayout is 0, the `to` address is liable for negative payouts *if* that occurs.
     * @param optionAddress The address of the longOptionTokes to close.
     * @param flashLoanQuantity The quantity of shortOptionTokens borrowed to use to close longOptionTokens.
     * @param minPayout The minimum payout of underlyingTokens sent to the `to` address.
     * @param to The address which is sent the underlyingToken payout, or liable to pay for a negative payout.
     */
    function flashCloseLongOptionsThenSwap(
        address optionAddress,
        uint256 flashLoanQuantity,
        uint256 minPayout,
        address to
    ) public override returns (uint256, uint256) {
        require(msg.sender == address(this), "ERR_NOT_SELF");
        require(to != address(0x0), "ERR_TO_ADDRESS_ZERO");
        require(to != msg.sender, "ERR_TO_MSG_SENDER");
        address underlyingToken =
            IOption(optionAddress).getUnderlyingTokenAddress();
        address redeemToken = IOption(optionAddress).redeemToken();

        (uint256 outputUnderlyings, uint256 underlyingPayout) =
            _flashCloseLongOptionsThenSwap(
                optionAddress,
                flashLoanQuantity,
                minPayout,
                to
            );

        // If underlyingPayout is non-zero and non-negative, send it to the `to` address.
        if (underlyingPayout > 0) {
            // Revert if minPayout is greater than the actual payout.
            require(underlyingPayout >= minPayout, "ERR_PREMIUM_UNDER_MIN");
            IERC20(underlyingToken).safeTransfer(to, underlyingPayout);
        }
        return (outputUnderlyings, underlyingPayout);
    }

    /**
     * @dev    Sends shortOptionTokens to msg.sender, and pays back the UniswapV2Pair in underlyingTokens.
     * @notice IMPORTANT: If minPayout is 0, the `to` address is liable for negative payouts *if* that occurs.
     * @param optionAddress The address of the longOptionTokes to close.
     * @param flashLoanQuantity The quantity of shortOptionTokens borrowed to use to close longOptionTokens.
     * @param minPayout The minimum payout of underlyingTokens sent to the `to` address.
     * @param to The address which is sent the underlyingToken payout, or liable to pay for a negative payout.
     */
    function flashCloseLongOptionsThenSwapForETH(
        address optionAddress,
        uint256 flashLoanQuantity,
        uint256 minPayout,
        address to
    ) public returns (uint256, uint256) {
        require(msg.sender == address(this), "ERR_NOT_SELF");
        require(to != address(0x0), "ERR_TO_ADDRESS_ZERO");
        require(to != msg.sender, "ERR_TO_MSG_SENDER");
        address underlyingToken =
            IOption(optionAddress).getUnderlyingTokenAddress();
        address redeemToken = IOption(optionAddress).redeemToken();

        (uint256 outputUnderlyings, uint256 underlyingPayout) =
            _flashCloseLongOptionsThenSwap(
                optionAddress,
                flashLoanQuantity,
                minPayout,
                to
            );

        // If underlyingPayout is non-zero and non-negative, send it to the `to` address.
        if (underlyingPayout > 0) {
            // Revert if minPayout is greater than the actual payout.
            require(underlyingPayout >= minPayout, "ERR_PREMIUM_UNDER_MIN");
            UniswapVenueLib.safeTransferWETHToETH(weth, to, underlyingPayout);
        }
        return (outputUnderlyings, underlyingPayout);
    }

    // ==== Callback Implementation ====

    /**
     * @dev The callback function triggered in a UniswapV2Pair.swap() call when the `data` parameter has data.
     * @param sender The original msg.sender of the UniswapV2Pair.swap() call.
     * @param amount0 The quantity of token0 received to the `to` address in the swap() call.
     * @param amount1 The quantity of token1 received to the `to` address in the swap() call.
     * @param data The payload passed in the `data` parameter of the swap() call.
     */
    function uniswapV2Call(
        address sender,
        uint256 amount0,
        uint256 amount1,
        bytes calldata data
    ) external override {
        address token0 = IUniswapV2Pair(msg.sender).token0();
        address token1 = IUniswapV2Pair(msg.sender).token1();
        assert(msg.sender == factory.getPair(token0, token1)); /// ensure that msg.sender is actually a V2 pair
        (bool success, bytes memory returnData) = address(this).call(data);
        require(
            success &&
                (returnData.length == 0 || abi.decode(returnData, (bool))),
            "ERR_UNISWAPV2_CALL_FAIL"
        );
    }

    // ==== View ====

    /**
     * @dev Gets the name of the contract.
     */
    function getName() external view override returns (string memory) {
        return capitol.venueState(address(this)).name;
    }

    /**
     * @dev Gets the version of the contract.
     */
    function getVersion() external view override returns (string memory) {
        return capitol.venueState(address(this)).apiVersion;
    }

    function getIsEndorsed() external view override returns (bool) {
        return capitol.getIsEndorsed(address(this));
    }

    /**
     * @dev    Calculates the effective premium, denominated in underlyingTokens, to "buy" `quantity` of optionTokens.
     * @notice UniswapV2 adds a 0.3009027% fee which is applied to the premium as 0.301%.
     *         IMPORTANT: If the pair's reserve ratio is incorrect, there could be a 'negative' premium.
     *         Buying negative premium options will pay out redeemTokens.
     *         An 'incorrect' ratio occurs when the (reserves of redeemTokens / strike ratio) >= reserves of underlyingTokens.
     *         Implicitly uses the `optionToken`'s underlying and redeem tokens for the pair.
     * @param  optionToken The optionToken to get the premium cost of purchasing.
     * @param  quantity The quantity of long option tokens that will be purchased.
     */
    function getOpenPremium(IOption optionToken, uint256 quantity)
        public
        view
        override
        returns (uint256, uint256)
    {
        return UniswapVenueLib.getOpenPremium(router, optionToken, quantity);
    }

    /**
     * @dev    Calculates the effective premium, denominated in underlyingTokens, to "sell" option tokens.
     * @param  optionToken The optionToken to get the premium cost of purchasing.
     * @param  quantity The quantity of short option tokens that will be closed.
     */
    function getClosePremium(IOption optionToken, uint256 quantity)
        public
        view
        override
        returns (uint256, uint256)
    {
        return UniswapVenueLib.getClosePremium(router, optionToken, quantity);
    }
}
