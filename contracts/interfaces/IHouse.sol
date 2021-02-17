pragma solidity >=0.6.2;

interface IHouse {
    function addCollateral(
        address wrappedToken,
        uint256 wrappedId,
        uint256 amount
    ) external returns (uint256);

    function addBatchCollateral(
        address wrappedToken,
        uint256[] calldata wrappedIds,
        uint256[] calldata amounts
    ) external returns (uint256);

    function removeCollateral(
        address wrappedToken,
        uint256 wrappedId,
        uint256 amount
    ) external returns (bool);

    function mintOptions(
        bytes32 oid,
        uint256 requestAmt,
        address[] calldata receivers
    ) external returns (bool);

    function exercise(
        bytes32 oid,
        uint256 amount,
        address receiver,
        bool fromInternal
    ) external returns (bool);

    function redeem(
        bytes32 oid,
        uint256 amount,
        address receiver,
        bool fromInternal
    ) external returns (bool);

    function close(
        bytes32 oid,
        uint256 amount,
        address receiver,
        bool fromInternal
    ) external returns (bool);

    function takeTokensFromUser(address token, uint256 quantity) external;

    // ==== View ====
    function getExecutingCaller() external view returns (address);

    function getOptionTokens(bytes32 oid) external returns (address, address);

    function getParameters(bytes32 oid)
        external
        view
        returns (
            address,
            address,
            uint256,
            uint32,
            uint8
        );

    function getCore() external view returns (address);
}
