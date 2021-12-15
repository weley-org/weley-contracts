pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/IERC721MetadataUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/IERC721EnumerableUpgradeable.sol";

interface IWeleyERC721 is
    IERC721MetadataUpgradeable,
    IERC721EnumerableUpgradeable
{
    function mint(address to, uint256 tokenId) external;

    function burn(uint256 tokenId) external;

    function tokensOfOwner(address owner)
        external
        view
        returns (uint256[] memory);

    function getTokenName(uint256 tokenId)
        external
        view
        returns (string memory);
}
