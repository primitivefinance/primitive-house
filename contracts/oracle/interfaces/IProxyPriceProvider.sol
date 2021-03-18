pragma solidity >=0.5.12 <=0.7.1;

interface IProxyPriceProvider {
    function getAssetPrice(address assetAddress)
        external
        view
        returns (uint256 price);

    function getAssetVolatility(address assetAddress)
        external
        view
        returns (uint256 volatility);

    function getCollateral(
        address token,
        uint256 wid,
        uint256 amount
    ) external view returns (uint256);

    function getBorrow(address token, uint256 debt)
        external
        view
        returns (uint256);
}
