pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "./IWeleyERC721.sol";

interface IWeleyNFT is IWeleyERC721 {
    struct TokenInfo {
        uint256 tokenId;
        uint256 level;
        uint256 power;
        string name;
        string res;
        address author;
    }

    struct Royalty {
        address payable account;
        uint96 value;
    }

    function mintNFT(
        address to,
        string memory nftName,
        uint256 quality,
        uint256 power,
        string memory res,
        address author
    ) external returns (uint256 tokenId);

    function totalPower() external view returns (uint256);

    function getNFT(uint256 id) external view returns (TokenInfo memory);

    function getRoyalties(uint256 tokenId)
        external
        view
        returns (Royalty[] memory);

    function sumRoyalties(uint256 tokenId) external view returns (uint256);

    function getPower(uint256 tokenId) external view returns (uint256);

    function getLevel(uint256 tokenId) external view returns (uint256);

    function tokenInfosOfOwner(address owner)
        external
        view
        returns (TokenInfo[] memory);

    function getTokenInfo(uint256 id) external view returns (TokenInfo memory);

    function getTokenInfos(uint256[] memory ids)
        external
        view
        returns (TokenInfo[] memory);

    function feeToken() external view returns (address);

    function getUpgradeFee(uint256 newLevel) external view returns (uint256);

    function upgradeNFT(uint256 nftId, uint256 materialNFTId) external;
}
