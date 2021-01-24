pragma solidity >=0.6.2;

interface IHouse {
    function doublePosition(
        address depositor,
        address longOption,
        uint256 quantity,
        address router,
        bytes calldata params
    ) external;

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
