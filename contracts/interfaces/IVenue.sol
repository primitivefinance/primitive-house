pragma solidity >=0.6.2;

interface IVenue {
    // adding liquidity returns quantity of lp tokens minted
    function deposit(bytes calldata params) external returns (uint256);

    // removing liquidity returns quantities of tokens withdrawn
    function withdraw(uint256 amount)
        external
        returns (address[] memory tokens, uint256[] memory amounts);

    function pool(address) external view returns (address);

    function swap(
        address[] calldata path,
        uint256 quantity,
        uint256 maxPremium
    ) external returns (uint256[] memory amounts);
}
