pragma solidity >=0.6.2;

/**
 * @title   Primitive Virtual Router -> Safe interfacing with virtual options.
 * @author  Primitive
 */

import {
    IOption
} from "@primitivefi/contracts/contracts/option/interfaces/IOption.sol";
import {PrimitiveRouterLib} from "./libraries/PrimitiveRouterLib.sol";
import {IPrimitiveRouter} from "./interfaces/IPrimitiveRouter.sol";
import {IWETH} from "./interfaces/IWETH.sol";

// Libraries
import {SafeMath} from "./libraries/SafeMath.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

contract VirtualRouter is IPrimitiveRouter {
    using SafeERC20 for IERC20;
    using SafeERC20 for IOption;
    using SafeMath for uint256;

    IWETH public weth;

    event Minted(
        address indexed from,
        address indexed optionToken,
        uint256 longQuantity,
        uint256 shortQuantity
    );
    event Exercised(
        address indexed from,
        address indexed optionToken,
        uint256 quantity
    );
    event Redeemed(
        address indexed from,
        address indexed optionToken,
        uint256 quantity
    );
    event Closed(
        address indexed from,
        address indexed optionToken,
        uint256 quantity
    );
    // multi-leg positions
    event VirtualMinted(
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

    /// @dev Checks the quantity of an operation to make sure its not zero. Fails early.
    modifier nonZero(uint256 quantity) {
        require(quantity > 0, "ERR_ZERO");
        _;
    }

    // ==== Constructor ====

    constructor(address weth_) public {
        require(address(weth) == address(0x0), "ERR_INITIALIZED");
        weth = IWETH(weth_);
        emit Initialized(msg.sender);
    }

    receive() external payable {
        assert(msg.sender == address(weth)); // only accept ETH via fallback from the WETH contract
    }

    // ==== Primitive Core ====

    /**
     * @dev Conducts important safety checks to safely mint option tokens.
     * @param optionToken The address of the option token to mint.
     * @param mintQuantity The quantity of option tokens to mint.
     * @param receiver The address which receives the minted option tokens.
     */
    function safeMint(
        IOption optionToken,
        uint256 mintQuantity,
        address receiver
    ) public nonZero(mintQuantity) returns (uint256, uint256) {
        IERC20(optionToken.getUnderlyingTokenAddress()).safeTransferFrom(
            msg.sender,
            address(this),
            mintQuantity
        );
        IOption virtualOption = IOption(virtualOptions[address(optionToken)]);
        Reserve memory reserve =
            _reserve[virtualOption.getUnderlyingTokenAddress()];
        reserve.virtualToken.mint(address(virtualOption), mintQuantity);
        emit Minted(
            msg.sender,
            address(optionToken),
            mintQuantity,
            PrimitiveRouterLib.getProportionalShortOptions(
                optionToken,
                mintQuantity
            )
        );
        return virtualOption.mintOptions(receiver);
    }

    /**
     * @dev Swaps strikeTokens to underlyingTokens using the strike ratio as the exchange rate.
     * @notice Burns optionTokens, option contract receives strikeTokens, user receives underlyingTokens.
     * @param optionToken The address of the option contract.
     * @param exerciseQuantity Quantity of optionTokens to exercise.
     * @param receiver The underlyingTokens are sent to the receiver address.
     */
    function safeExercise(
        IOption optionToken,
        uint256 exerciseQuantity,
        address receiver
    ) public nonZero(exerciseQuantity) returns (uint256, uint256) {
        // Calculate quantity of strikeTokens needed to exercise quantity of optionTokens.
        address strikeToken = optionToken.getStrikeTokenAddress();
        uint256 inputStrikes =
            PrimitiveRouterLib.getProportionalShortOptions(
                optionToken,
                exerciseQuantity
            );
        IERC20(address(optionToken)).safeTransferFrom(
            msg.sender,
            address(optionToken),
            exerciseQuantity
        );
        IERC20(strikeToken).safeTransferFrom(
            msg.sender,
            address(optionToken),
            inputStrikes
        );
        emit Exercised(msg.sender, address(optionToken), exerciseQuantity);
        return
            optionToken.exerciseOptions(
                receiver,
                exerciseQuantity,
                new bytes(0)
            );
    }

    /**
     * @dev Burns redeemTokens to withdraw available strikeTokens.
     * @notice inputRedeems = outputStrikes.
     * @param optionToken The address of the option contract.
     * @param redeemQuantity redeemQuantity of redeemTokens to burn.
     * @param receiver The strikeTokens are sent to the receiver address.
     */
    function safeRedeem(
        IOption optionToken,
        uint256 redeemQuantity,
        address receiver
    ) public nonZero(redeemQuantity) returns (uint256) {
        IOption virtualOption = IOption(virtualOptions[address(optionToken)]);
        IERC20(virtualOption.redeemToken()).safeTransferFrom(
            msg.sender,
            address(virtualOption),
            redeemQuantity
        );
        Reserve memory reserve =
            _reserve[virtualOption.getStrikeTokenAddress()];
        emit Redeemed(msg.sender, address(optionToken), redeemQuantity);
        uint256 strikesRedeemed = virtualOption.redeemStrikeTokens(receiver);
        reserve.virtualToken.burn(address(this), redeemQuantity);
        return
            IERC20(optionToken.getStrikeTokenAddress()).safeTransfer(
                receiver,
                strikesRedeemed
            );
    }

    /**
     * @dev Burn optionTokens and redeemTokens to withdraw underlyingTokens.
     * @notice The redeemTokens to burn is equal to the optionTokens * strike ratio.
     * inputOptions = inputRedeems / strike ratio = outUnderlyings
     * @param optionToken The address of the option contract.
     * @param closeQuantity Quantity of optionTokens to burn.
     * (Implictly will burn the strike ratio quantity of redeemTokens).
     * @param receiver The underlyingTokens are sent to the receiver address.
     */
    function safeClose(
        IOption optionToken,
        uint256 closeQuantity,
        address receiver
    )
        public
        nonZero(closeQuantity)
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        // Calculate the quantity of redeemTokens that need to be burned. (What we mean by Implicit).
        uint256 inputRedeems =
            PrimitiveRouterLib.getProportionalShortOptions(
                optionToken,
                closeQuantity
            );
        IERC20(optionToken.redeemToken()).safeTransferFrom(
            msg.sender,
            address(optionToken),
            inputRedeems
        );
        if (optionToken.getExpiryTime() >= now)
            IERC20(address(optionToken)).safeTransferFrom(
                msg.sender,
                address(optionToken),
                closeQuantity
            );
        emit Closed(msg.sender, address(optionToken), closeQuantity);
        return optionToken.closeOptions(receiver);
    }

    // ==== Primitive Core WETH  Abstraction ====

    /**
     *@dev Mints msg.value quantity of options and "quote" (option parameter) quantity of redeem tokens.
     *@notice This function is for options that have WETH as the underlying asset.
     *@param optionToken The address of the option token to mint.
     *@param receiver The address which receives the minted option and redeem tokens.
     */
    function safeMintWithETH(IOption optionToken, address receiver)
        public
        payable
        nonZero(msg.value)
        returns (uint256, uint256)
    {
        // Check to make sure we are minting a WETH call option.
        address underlyingAddress = optionToken.getUnderlyingTokenAddress();
        require(address(weth) == underlyingAddress, "ERR_NOT_WETH");

        // Convert ethers into WETH, then send WETH to option contract in preparation of calling mintOptions().
        PrimitiveRouterLib.safeTransferETHFromWETH(
            weth,
            address(optionToken),
            msg.value
        );
        emit Minted(
            msg.sender,
            address(optionToken),
            msg.value,
            PrimitiveRouterLib.getProportionalShortOptions(
                optionToken,
                msg.value
            )
        );
        return optionToken.mintOptions(receiver);
    }

    /**
     * @dev Swaps msg.value of strikeTokens (ethers) to underlyingTokens.
     * Uses the strike ratio as the exchange rate. Strike ratio = base / quote.
     * Msg.value (quote units) * base / quote = base units (underlyingTokens) to withdraw.
     * @notice This function is for options with WETH as the strike asset.
     * Burns option tokens, accepts ethers, and pushes out underlyingTokens.
     * @param optionToken The address of the option contract.
     * @param receiver The underlyingTokens are sent to the receiver address.
     */
    function safeExerciseWithETH(IOption optionToken, address receiver)
        public
        payable
        nonZero(msg.value)
        returns (uint256, uint256)
    {
        // Require one of the option's assets to be WETH.
        address strikeAddress = optionToken.getStrikeTokenAddress();
        require(strikeAddress == address(weth), "ERR_NOT_WETH");

        uint256 inputStrikes = msg.value;
        // Calculate quantity of optionTokens needed to burn.
        // An ether put option with strike price $300 has a "base" value of 300, and a "quote" value of 1.
        // To calculate how many options are needed to be burned, we need to cancel out the "quote" units.
        // The input strike quantity can be multiplied by the strike ratio to cancel out "quote" units.
        // 1 ether (quote units) * 300 (base units) / 1 (quote units) = 300 inputOptions
        uint256 inputOptions =
            PrimitiveRouterLib.getProportionalLongOptions(
                optionToken,
                inputStrikes
            );

        // Wrap the ethers into WETH, and send the WETH to the option contract to prepare for calling exerciseOptions().
        PrimitiveRouterLib.safeTransferETHFromWETH(
            weth,
            address(optionToken),
            msg.value
        );
        IERC20(address(optionToken)).safeTransferFrom(
            msg.sender,
            address(optionToken),
            inputOptions
        );

        // Burns the transferred option tokens, stores the strike asset (ether), and pushes underlyingTokens
        // to the receiver address.
        emit Exercised(msg.sender, address(optionToken), inputOptions);
        return
            optionToken.exerciseOptions(receiver, inputOptions, new bytes(0));
    }

    /**
     * @dev Swaps strikeTokens to underlyingTokens, WETH, which is converted to ethers before withdrawn.
     * Uses the strike ratio as the exchange rate. Strike ratio = base / quote.
     * @notice This function is for options with WETH as the underlying asset.
     * Burns option tokens, pulls strikeTokens, and pushes out ethers.
     * @param optionToken The address of the option contract.
     * @param exerciseQuantity Quantity of optionTokens to exercise.
     * @param receiver The underlyingTokens (ethers) are sent to the receiver address.
     */
    function safeExerciseForETH(
        IOption optionToken,
        uint256 exerciseQuantity,
        address receiver
    ) public nonZero(exerciseQuantity) returns (uint256, uint256) {
        // Require one of the option's assets to be WETH.
        address underlyingAddress = optionToken.getUnderlyingTokenAddress();
        require(underlyingAddress == address(weth), "ERR_NOT_WETH");

        (uint256 inputStrikes, uint256 inputOptions) =
            safeExercise(optionToken, exerciseQuantity, address(this));

        // Converts the withdrawn WETH to ethers, then sends the ethers to the receiver address.
        PrimitiveRouterLib.safeTransferWETHToETH(
            weth,
            receiver,
            exerciseQuantity
        );
        return (inputStrikes, inputOptions);
    }

    /**
     * @dev Burns redeem tokens to withdraw strike tokens (ethers) at a 1:1 ratio.
     * @notice This function is for options that have WETH as the strike asset.
     * Converts WETH to ethers, and withdraws ethers to the receiver address.
     * @param optionToken The address of the option contract.
     * @param redeemQuantity The quantity of redeemTokens to burn.
     * @param receiver The strikeTokens (ethers) are sent to the receiver address.
     */
    function safeRedeemForETH(
        IOption optionToken,
        uint256 redeemQuantity,
        address receiver
    ) public nonZero(redeemQuantity) returns (uint256) {
        // If options have not been exercised, there will be no strikeTokens to redeem, causing a revert.
        // Burns the redeem tokens that were sent to the contract, and withdraws the same quantity of WETH.
        // Sends the withdrawn WETH to this contract, so that it can be unwrapped prior to being sent to receiver.
        uint256 inputRedeems =
            safeRedeem(optionToken, redeemQuantity, address(this));
        // Unwrap the redeemed WETH and then send the ethers to the receiver.
        PrimitiveRouterLib.safeTransferWETHToETH(
            weth,
            receiver,
            redeemQuantity
        );
        return inputRedeems;
    }

    /**
     * @dev Burn optionTokens and redeemTokens to withdraw underlyingTokens (ethers).
     * @notice This function is for options with WETH as the underlying asset.
     * WETH underlyingTokens are converted to ethers before being sent to receiver.
     * The redeemTokens to burn is equal to the optionTokens * strike ratio.
     * inputOptions = inputRedeems / strike ratio = outUnderlyings
     * @param optionToken The address of the option contract.
     * @param closeQuantity Quantity of optionTokens to burn and an input to calculate how many redeems to burn.
     * @param receiver The underlyingTokens (ethers) are sent to the receiver address.
     */
    function safeCloseForETH(
        IOption optionToken,
        uint256 closeQuantity,
        address receiver
    )
        public
        nonZero(closeQuantity)
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        (uint256 inputRedeems, uint256 inputOptions, uint256 outUnderlyings) =
            safeClose(optionToken, closeQuantity, address(this));

        // Since underlyngTokens are WETH, unwrap them then send the ethers to the receiver.
        PrimitiveRouterLib.safeTransferWETHToETH(weth, receiver, closeQuantity);
        return (inputRedeems, inputOptions, outUnderlyings);
    }

    // ==== End Core ====

    // Position operations

    function openDebitSpread(
        address longOption,
        address shortOption,
        uint256 quantity,
        address receiver
    ) external {
        // assume these are calls for now
        IOption virtualLong = IOption(virtualOptions[longOption]);
        IOption virtualShort = IOption(virtualOptions[shortOption]);

        // Check to make sure long option sufficiently covers short option.
        uint256 longStrike = virtualLong.getQuoteValue();
        uint256 shortStrike = virtualShort.getQuoteValue();
        require(shortStrike >= longStrike, "ERR_CREDIT_SPREAD");

        // e.g. short a 500 call and long a 400 call. 100 strike difference.
        uint256 strikeDifference = shortStrike.sub(longStrike);

        // Get virtual token from reserve.
        ReserveData storage reserve =
            _reserves[IOption(shortOption).getUnderlyingTokenAddress()];

        // Mint virtual tokens to the virtual short option.
        reserve.virtualToken.mint(address(virtualShort), quantity);

        // Mint virtual option and redeem tokens to this contract.
        virtualShort.mintOptions(address(this));

        // Send out virtual option tokens.
        virtualShort.transfer(receiver, quantity);

        // Send out strikeDifference quantity of virtual redeem tokens.
        IERC20(virtualShort.redeemToken()).transfer(receiver, strikeDifference);

        // Pull in the original long option.
        virtualLong.safeTransferFrom(msg.sender, address(this), quantity);

        emit OpenedDebitSpread(msg.sender, longOption, shortOption, quantity);

        // Final balance sheet:
        //
        // House
        // Quantity# of long option tokens
        // strikeDiff# of virtual short option (redeem) tokens
        //
        // Receiver
        // Quantity# of virtual long option tokens (which can then be sold)
        // 1 - strikeDiff# of virtual short option (redeem) tokens
    }

    // Option operations

    function virtualMint(
        address optionAddress,
        uint256 quantity,
        address receiver
    ) external returns (address) {
        _virtualMint(optionAddress, quantity, receiver);
        // Pull real tokens to this contract.
        _pullTokens(underlying, quantity);
        return virtualOption;
    }

    function virtualMintFrom(
        address from,
        address optionAddress,
        uint256 quantity,
        address receiver
    ) external returns (address) {
        _virtualMint(optionAddress, quantity, receiver);
        // Pull real tokens to this contract.
        _pullTokensFrom(from, underlying, quantity);
        return virtualOption;
    }

    function _virtualMint(
        address optionAddress,
        uint256 quantity,
        address receiver
    ) external returns (address) {
        address virtualOption = virtualOptions[optionAddress];
        require(virtualOption != address(0x0), "ERR_NOT_DEPLOYED");

        // Store in memory for gas savings.
        address underlying = IOption(optionAddress).getUnderlyingTokenAddress();

        // Get virtual token from reserve.
        ReserveData storage reserve = _reserves[underlying];

        // Mint virtual tokens to the virtual option contract.
        reserve.virtualToken.mint(virtualOption, quantity);

        // Call mintOptions and send options to the receiver address.
        IOption(virtualOption).mintOptions(receiver);
        emit VirtualMinted(msg.sender, optionAddress, quantity);
        return virtualOption;
    }

    function virtualExercise(
        address optionAddress,
        uint256 quantity,
        address receiver
    ) external {
        address virtualOption = virtualOptions[optionAddress];
        require(virtualOption != address(0x0), "ERR_NOT_DEPLOYED");

        // Store in memory for gas savings.
        address underlying = IOption(optionAddress).getUnderlyingTokenAddress();
        address strike = IOption(optionAddress).getStrikeTokenAddress();

        // Move virtual options from msg.sender to virtual option contract itself.
        IERC20(virtualOption).safeTransferFrom(
            msg.sender,
            virtualOption,
            quantity
        );

        // Calculate strike tokens needed to exercise.
        uint256 amountStrikeTokens =
            calculateStrikePayment(optionAddress, quantity);

        // Mint required strike tokens to the virtual option in preparation of calling exerciseOptions().
        _reserves[strike].virtualToken.mint(virtualOption, amountStrikeTokens);

        // Call exerciseOptions and send underlying tokens to this contract.
        IOption(virtualOption).exerciseOptions(
            address(this),
            quantity,
            new bytes(0)
        );

        // Burn the virtual underlying tokens.
        _reserves[underlying].virtualToken.burn(address(this), quantity);

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

    function _pullTokensFrom(
        address from,
        address token,
        uint256 quantity
    ) internal {
        IERC20(token).safeTransferFrom(from, address(this), quantity);
    }
}
