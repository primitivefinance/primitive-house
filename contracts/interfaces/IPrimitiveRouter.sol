// SPDX-License-Identifier: MIT
pragma solidity >=0.6.2;

import {
    IOption,
    IERC20
} from "@primitivefi/contracts/contracts/option/interfaces/IOption.sol";

interface IPrimitiveRouter {
    
    function safeMint(
        IOption optionToken,
        uint256 mintQuantity,
        address receiver
    ) external returns (uint256, uint256);

    function safeMintWithETH(IOption optionToken, address receiver)
        external
        payable
        returns (uint256, uint256);

    function safeExercise(
        IOption optionToken,
        uint256 exerciseQuantity,
        address receiver
    ) external returns (uint256, uint256);

     function safeExerciseWithETH(IOption optionToken, address receiver)
        external
        payable
        returns (uint256, uint256);

        function safeExerciseForETH(
        IOption optionToken,
        uint256 exerciseQuantity,
        address receiver
    ) external returns (uint256, uint256);

    function safeRedeem(
        IOption optionToken,
        uint256 redeemQuantity,
        address receiver
    ) external returns (uint256);

    function safeRedeemForETH(
        IOption optionToken,
        uint256 redeemQuantity,
        address receiver
    ) external  returns (uint256);

    function safeClose(
        IOption optionToken,
        uint256 closeQuantity,
        address receiver
    )
        external
        returns (
            uint256,
            uint256,
            uint256
        );

    function safeCloseForETH(
        IOption optionToken,
        uint256 closeQuantity,
        address receiver
    )
        external
        returns (
            uint256,
            uint256,
            uint256
        );

    function safeUnwind(
        IOption optionToken,
        uint256 unwindQuantity,
        address receiver
    )
        external
        returns (
            uint256,
            uint256,
            uint256
        );
}