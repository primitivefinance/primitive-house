pragma solidity >=0.6.2;

/**
 * @title The Base Venue contract to facilitate interactions with the House.
 */

// Open Zeppelin
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import {IERC20} from "./interfaces/IERC20.sol";
import {IHouse} from "./interfaces/IHouse.sol";
import {IWETH} from "./interfaces/IWETH.sol";
import {
    IOption
} from "@primitivefi/contracts/contracts/option/interfaces/IOption.sol";

contract BaseVenue {
    using SafeERC20 for IERC20;

    IWETH public weth;
    IHouse public house;

    mapping(address => mapping(address => bool)) public isMaxApproved;

    constructor(address weth_, address house_) public {
        weth = IWETH(weth_);
        house = IHouse(house_);
        checkApproved(weth_, house_);
    }

    receive() external payable {
        assert(msg.sender == address(weth)); // only accept ETH via fallback from the WETH contract
    }

    // ==== Utility ====

    function checkApproved(address token, address spender) public {
        if (isMaxApproved[token][spender]) {
            return;
        } else {
            IERC20(token).approve(spender, uint256(-1));
            isMaxApproved[token][spender] = true;
        }
    }

    // ==== Actions ====

    function _convertETH() internal {
        if (msg.value > 0) {
            weth.deposit.value(msg.value)();
        }
    }

    function _takeWETHDust() internal {
        uint256 bal = IERC20(address(weth)).balanceOf(address(this));
        if (bal > 0) {
            weth.withdraw(bal);
            (bool success, ) = house.CALLER().call{value: bal}(new bytes(0));
            require(success, "BaseVenue: SEND_ETH_BACK");
        }
    }

    function _mintOptions(
        address optionAddress,
        uint256 quantity,
        address longReceiver,
        address shortReceiver
    ) internal {
        if (quantity > 0) {
            house.mintVirtualOptions(
                optionAddress,
                quantity,
                longReceiver,
                shortReceiver
            );
        }
    }

    function _burnOptions(
        address optionAddress,
        uint256 quantity,
        address receiver
    ) internal {
        if (quantity > 0) {
            house.burnVirtualOptions(optionAddress, quantity, receiver);
        }
    }

    function _lendSingle(address token, uint256 amount) internal {
        address[] memory tokens = new address[](1);
        tokens[0] = token;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;
        _lendMultiple(tokens, amounts);
    }

    function _lendMultiple(address[] memory tokens, uint256[] memory amounts)
        internal
    {
        house.addTokens(house.CALLER(), tokens, amounts);
    }

    function _borrowSingle(address token, uint256 amount) internal {
        address[] memory tokens = new address[](1);
        tokens[0] = token;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;
        _borrowMultiple(tokens, amounts);
    }

    function _borrowMultiple(address[] memory tokens, uint256[] memory amounts)
        internal
    {
        house.removeTokens(house.CALLER(), tokens, amounts);
    }

    // Pulls tokens from user and sends them to the house.
    function _takeTokens(address token, uint256 quantity) internal {
        if (quantity > 0) {
            house.takeTokensFromUser(token, quantity);
        }
    }

    function _takeDust(address token) internal {
        uint256 bal = IERC20(token).balanceOf(address(this));
        if (bal > 0) {
            IERC20(token).transfer(house.CALLER(), bal);
        }
    }
}
