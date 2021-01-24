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
import {Accelerator} from "./extensions/Accelerator.sol";
import {ICapitol} from "./interfaces/ICapitol.sol";
import {IERC20} from "./interfaces/IERC20.sol";
import {IVERC20} from "./interfaces/IVERC20.sol";
import {IPrimitiveRouter} from "./interfaces/IPrimitiveRouter.sol";
import {IVenue} from "./interfaces/IVenue.sol";
import {IWETH} from "./interfaces/IWETH.sol";
import {RouterLib} from "./libraries/RouterLib.sol";
import {SafeMath} from "./libraries/SafeMath.sol";
import {VirtualRouter} from "./VirtualRouter.sol";

contract House is VirtualRouter, Accelerator {
    /* using SafeERC20 for IERC20; */
    using SafeMath for uint256;

    struct Account {
        mapping(address => uint256) balanceOf;
    }

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

    ICapitol public capitol;

    mapping(address => mapping(address => uint256)) public debit;
    mapping(address => mapping(address => uint256)) public credit;

    modifier isEndorsed(address venue_) {
        require(capitol.getIsEndorsed(venue_), "House: NOT_ENDORSED");
        _;
    }

    constructor(
        address weth_,
        address registry_,
        address energy_,
        address capitol_
    ) public VirtualRouter(weth_, registry_) Accelerator(energy_) {
        capitol = ICapitol(capitol_);
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
            IERC20(asset).transferFrom(depositor, address(this), quantity);
        }
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
                credit[asset][depositor] = credit[asset][depositor].add(
                    quantity
                );
            }
        }
        emit CollateralDeposited(depositor, tokens, amounts);
        return true;
    }

    function removeTokens(
        address depositor,
        address[] memory tokens,
        uint256[] memory amounts
    ) public returns (bool) {
        // Remove balances from state.
        _removeTokens(depositor, tokens, amounts, true);
        uint256 tokensLength = tokens.length;
        for (uint256 i = 0; i < tokensLength; i++) {
            // Push tokens to depositor.
            address asset = tokens[i];
            uint256 quantity = amounts[i];
            IERC20(asset).transfer(depositor, quantity);
        }
        return true;
    }

    function _removeTokens(
        address depositor,
        address[] memory tokens,
        uint256[] memory amounts,
        bool isDebit
    ) internal returns (bool) {
        uint256 tokensLength = tokens.length;
        uint256 amountsLength = amounts.length;
        require(tokensLength == amountsLength, "House: PARAMETER_LENGTH");
        for (uint256 i = 0; i < tokensLength; i++) {
            // Remove liquidity to a depositor's respective pool balance.
            address asset = tokens[i];
            uint256 quantity = amounts[i];
            if (isDebit) {
                debit[asset][depositor] = debit[asset][depositor].sub(quantity);
            } else {
                credit[asset][depositor] = credit[asset][depositor].sub(
                    quantity
                );
            }
        }
        emit CollateralWithdrawn(depositor, tokens, amounts);
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

    // ==== No leverage ====

    // ==== 2x leverage ====

    /**
     * @dev     Mints short option tokens virtually, to deposit them into the market.
     * @notice  Hold LP tokens as collateral, attribute to original depositor.
     */
    function doublePosition(
        address depositor,
        address longOption,
        uint256 quantity,
        address router,
        bytes memory params
    ) public {
        // mint virtual options to this contract.
        // pulls quantity of underlying tokens from depositor.
        virtualMintFrom(depositor, longOption, quantity, address(this));
        // add liquidity and store LP tokens, attribute to depositor.
        _doublePosition(depositor, longOption, quantity, router, params);
    }

    /**
     * @dev     Performs a low level call to the venue's desired contract with desired parameters.
     * @notice  Sends virtual redeem tokens and real underlying tokens out to the called contract.
     *          Stores LP tokens as collateral, attributed to original depositor.
     *          Emits the "Leveraged" event.
     * @param   depositor The address of the original caller whom is providing liquidity.
     * @param   longOption The address of the long option token to provide liquidity to its virtual counter-part.
     * @param   quantity The amount of real underlying tokens that will be sent from this contract to the pool.
     * @param   router The contract performing the transfer between this contract and the core pool.
     * @param   params The arguments specified to make the call, unknown abi to this contract.
     */
    function _doublePosition(
        address depositor,
        address longOption,
        uint256 quantity,
        address router,
        bytes memory params
    ) internal isEndorsed(msg.sender) {
        IOption virtualLong = IOption(virtualOptions[longOption]);
        // get the data to call to deposit into the respective venue's pool.
        // Example: UniswapVendor, the function we are calling with `params` is `addLiquidity`.
        address redeem = virtualLong.redeemToken(); // virtual version of the redeem
        address underlying = IOption(longOption).getUnderlyingTokenAddress(); // actual underlying
        // gets the pool's address (the lp token address) to apply it to the depositor's internal balance.
        address pool = IVenue(msg.sender).pool(longOption);
        IERC20(redeem).approve(address(router), uint256(-1)); // approves the router to transferFrom this redeem
        IERC20(underlying).approve(address(router), uint256(-1)); // approves the router to transferFrom this underlying

        // this call will pull the underlyingTokens received from the virtual mint,
        // and the short options which were virtualally minted.
        // They will be pulled into the pool, which will issue LP tokens to this contract.
        (bool success, bytes memory returnData) = router.call(params);
        require(success, "ERR_POOL_DEPOSIT_FAIL");

        (uint256 amountA, uint256 amountB, uint256 liquidity) =
            abi.decode(returnData, (uint256, uint256, uint256));

        address[] memory tokens = new address[](1);
        tokens[0] = pool;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = liquidity;

        /* _addTokens(depositor, tokens, amounts, true);

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

        emit Leveraged(depositor, address(virtualLong), pool, quantity); */
    }

    // ==== 2x Deleverage ====

    function doubleUnwind(
        address depositor,
        address option,
        uint256 quantity,
        address router,
        bytes memory params
    ) public {
        _doubleUnwind(depositor, option, quantity, router, params);
    }

    function _doubleUnwind(
        address depositor,
        address option,
        uint256 quantity,
        address router,
        bytes memory params
    ) internal isEndorsed(msg.sender) {
        address pool = IVenue(msg.sender).pool(option);
        // get depositor balance of liquidity and then call withdraw() on venue
        uint256 liquidity = 1; //bank[depositor][pool];
        address[] memory tokens = new address[](1);
        tokens[0] = pool;

        uint256[] memory quantities = new uint256[](1);
        quantities[0] = liquidity;
        // update balance
        _removeTokens(depositor, tokens, quantities, false);

        // withdraw liquidity to get return tokens and their amounts back to this contract.
        //(address[] memory tokens, uint[] memory amounts) = IVenue(msg.sender).withdraw(liquidity);

        // Example: uniswap. Calls removeLiquidity, which will have the unirouter pull lp tokens from this contract.
        // After burning lp tokens, released tokens of the pair will be returned here.
        (bool success, bytes memory returnData) = router.call(params);
        require(success, "ERR_POOL_WITHDRAW_FAIL");
        uint256[] memory amounts = abi.decode(returnData, (uint256[]));

        // example:
        // ETH      1
        // Short    3
        //
        // Need to determine how which tokens and how many to send back to depositor...
        // Depositor originally deposited 2 ETH, so they are entitled to half the returned tokens.
        //
        // House currently has
        // Long     2
        //
        // House needs to close its liability and clear its balance sheet
        // Long     2
        // Short    2
        // ----------
        // Long     0
        // Short    0
        // Short    1 (from LP)
        // ETH      1 (from LP)
        //
        // Return 1 ETH and 1 Short to the original depositor.
        // So we can take the sum of the outputs (assuming proportional), divide by 2, which gives us x
        // then we close x amount of options, and return amounts-x = remainder of tokens withdrawn from lp
        // Get virtual token from reserve.
        /* address virtualOption = virtualOptions[option];
        address redeem = IOption(option).redeemToken();
        address underlying = IOption(option).getUnderlyingTokenAddress();
        ReserveData memory reserve = _reserves[redeem];
        address virtualRedeem = address(reserve.virtualToken);
        uint256 sum;
        uint256 amountsLength = amounts.length;
        for (uint256 i = 0; i < amountsLength; i++) {
            uint256 amount = amounts[i];
            sum = sum.add(amount);
        }

        uint256 x = sum.div(2);

        // close the option, 4 transfers...
        IERC20(virtualRedeem).transfer(virtualOption, x);
        IERC20(virtualOption).transfer(virtualOption, x);
        IOption(virtualOption).closeOptions(address(this));
        // Get virtual token from reserve.
        ReserveData memory reserveU = _reserves[underlying];
        // Burn virtual tokens from this contract.
        reserveU.virtualToken.burn(address(this), x); // fix x

        // return the assets
        // if original sum was 4, 1 ETH + 3 Short, then 4/2 = 2 Short were burned.
        // Which means 1 ETH + 1 Short Remains. Which is x/2 = 1 each.
        // where 4/2 = sum / 2, and 2/2 = sum/2 / 2.
        // amountA = 3, 3 - 4/2 = 1 Short
        // amountB = 1, 2 - 2/2 = 1 ETH
        IERC20(underlying).transfer(depositor, x.div(2));
        IERC20(virtualRedeem).transfer(depositor, x.div(2));
        emit Deleveraged(depositor, option, liquidity); */
    }

    // ==== 4x leverage ====

    function quadPosition(
        address depositor,
        address longOption,
        uint256 quantity,
        address router,
        bytes memory params
    ) public {
        // Depositor 2 ETH
        // Bank      2 ETH (matches)
        //
        // Deposits 4 ETH + 4 Short in LP
        //
        // Example, withdraws liquidity later and receives:
        // ETH      2
        // Short    6
        //
        // Need to determine how which tokens and how many to send back to depositor...
        // Depositor originally deposited 4 ETH, with 2x leverage, a total of 8.
        // so they are entitled to half the returned tokens.
        //
        // House currently has
        // Long     4
        //
        // House needs to close its liability and clear its balance sheet
        // LIABILITIES
        // Long     4
        // Short    4
        // ETH      -2
        // ----------
        // AFTER BURNING
        // ----------
        // Long     0
        // Short    0
        // Short    6 (from LP) - 4 (Liability) = 2 Short
        // ETH      2 (from LP) - 2 (Liability) = 0 ETH
        //
        // Lender
        // ---------
        // ETH      2
        //
        // Return 0 ETH and 2 Short to the original depositor.
        // So we can take the sum of the outputs (assuming proportional), divide by 2, which gives us x. 8 / 2 = x.
        // then we close x amount of options, and return amounts-x = remainder of tokens withdrawn from lp
        // amountA - sum / 2 = remaining Short
        // amountB - sum / 2 / 2 = remaining ETH
        // amountA-4 = remaining short
        // amountB-4/2 = remaining ETH (borrowed)
        // amountA = 6, 6-4= 2 Short
        // amountB = 2, 2 - 4/2 = 0 ETH
        // mint virtual options to this contract.
        // pulls quantity of underlying tokens from depositor.
        // borrows quantity of underlying tokens from energy.
        uint256 total = quantity.add(quantity);
        _virtualMint(longOption, total, address(this));
        _pullTokensFrom(
            depositor,
            IOption(longOption).getUnderlyingTokenAddress(),
            quantity
        );
        energy.draw(address(this), quantity);
        _doublePosition(depositor, longOption, total, router, params);
    }
}
