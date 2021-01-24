pragma solidity >=0.6.2;

interface ICapitol {
    function addVenue(
        address venue_,
        string calldata name,
        string calldata apiVersion,
        bool isEndorsed
    ) external;

    function endorse(address venue_) external;

    function getIsEndorsed(address venue_) external view returns (bool);

    function getVenuesLength() external view returns (uint256);

    function getVenueAttributes(address venue_)
        external
        view
        returns (
            string memory,
            string memory,
            bool
        );
}
