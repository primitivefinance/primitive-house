pragma solidity >=0.6.2;

interface IHouse {
    event Executed(address indexed from, address indexed venue);
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

    function virtualOptions(address optionAddress)
        external
        view
        returns (address);

    // Creates virtual options without collateral.
    function mintVirtualOptions(
        address optionAddress,
        uint256 quantity,
        address longReceiver,
        address shortReceiver
    ) external;

    // Burns virtual options.
    function burnVirtualOptions(
        address optionAddress,
        uint256 quantity,
        address receiver
    ) external;

    // Deposits tokens as collateral to the House.
    function addTokens(
        address depositor,
        address[] calldata tokens,
        uint256[] calldata amounts
    ) external returns (bool);

    // Withdraws tokens from collateral stored the House.
    function removeTokens(
        address withdrawee,
        address[] calldata tokens,
        uint256[] calldata amounts
    ) external returns (bool);

    function takeTokensFromUser(address token, uint256 quantity) external;

    // ==== View ====
    function CALLER() external view returns (address);
}
