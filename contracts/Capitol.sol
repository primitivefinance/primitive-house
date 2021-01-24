pragma solidity >=0.6.2;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IVenue} from "./interfaces/IVenue.sol";
import {ICapitol} from "./interfaces/ICapitol.sol";

contract Capitol is Ownable, ICapitol {
    struct VenueAttributes {
        string name;
        string apiVersion;
        bool isEndorsed;
    }

    mapping(address => VenueAttributes) public venueState;
    IVenue[] public allVenues;

    constructor() public {}

    function addVenue(
        address venue_,
        string memory name,
        string memory apiVersion,
        bool isEndorsed
    ) public override onlyOwner {
        VenueAttributes storage venue = venueState[venue_];
        venue.name = name;
        venue.apiVersion = apiVersion;
        venue.isEndorsed = isEndorsed;
        allVenues.push(IVenue(venue_));
    }

    function endorse(address venue_) public override onlyOwner {
        VenueAttributes memory venue = venueState[venue_];
        venue.isEndorsed = true;
    }

    function getIsEndorsed(address venue_) public view override returns (bool) {
        VenueAttributes memory venue = venueState[venue_];
        return venue.isEndorsed;
    }

    function getVenuesLength() public view override returns (uint256) {
        return allVenues.length;
    }

    function getVenueAttributes(address venue_)
        public
        view
        override
        returns (
            string memory,
            string memory,
            bool
        )
    {
        VenueAttributes memory venue = venueState[venue_];
        return (venue.name, venue.apiVersion, venue.isEndorsed);
    }
}
