pragma solidity >=0.6.2;


import {IUniswapConnector03, IUniswapV2Factory} from "@primitivefi/v1-connectors/contracts/interfaces/IUniswapConnector03.sol";
import {Venue} from "../Venue.sol"; 
contract UniswapVenue is Venue {

    IUniswapConnector03 public connector;
    IHouse public house;

    bytes4 internal constant ADD_LIQUIDITY = 0x2e16cab3;

    constructor(address uniswapConnector_, address house_) public {
        connector = IUniswapConnector03(uniswapConnector_);
        house = IHouse(house_);
    }

    function pool(address option) external override returns(address) {
        address underlying = IOption(option).getUnderlyingTokenAddress();
        address redeem = IOption(option).redeemToken();
        address pair = connector.factory.getPair(underlying, redeem);
        return pair;
    }

    // User will enter pool with various amounts of leverage.
    function enter(
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
        uint total = quantityOptions.add(amountBMax); // the total deposit quantity in underlying tokens
        uint outputRedeems = connector.proportionalShort(total); // the synthetic short options minted from total deposit
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
        
        IUniswapV2Router02 router = connector.router;
        // calls the house to double the position and store the lp tokens as collateral
        // house will call the `params` data to the router.
        house.doublePosition(msg.sender, optionAddress, total, address(router), params);
    }

    function deposit(bytes memory params) external override returns (bytes memory) {
        assert(msg.sender == address(house)); /// ensure that msg.sender is actually the house
        (bool success, bytes memory returnData) = router.call(params);
        require(
            success &&
                (returnData.length == 0 || abi.decode(returnData, (bool))),
            "ERR_CONNECTOR_CALL_FAIL"
        );
        return returnData;
    }

    function withdraw(
        address optionAddress,
        uint256 quantityOptions,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
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
        
        IUniswapV2Router02 router = connector.router;
        // calls the house to double the position and store the lp tokens as collateral
        // house will call the `params` data to the router.
        house.doubleUnwind(msg.sender, optionAddress, liquidity, address(router), params);
    }
}   