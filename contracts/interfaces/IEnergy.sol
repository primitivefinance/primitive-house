pragma solidity >=0.6.2;

interface IEnergy {
    function erase(address receiver, uint256 amount) external returns (uint256);

    function draw(address receiver, uint256 amount) external returns (uint256);

    function debit() external view returns (uint256);

    function credit() external view returns (uint256);
}
