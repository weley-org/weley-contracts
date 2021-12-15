pragma solidity ^0.8.0;
import "./IWeleyERC721.sol";

interface IMysteryBox is IWeleyERC721 {
    struct Category {
        uint256 id;
        string name;
        string res;
        address nft;
        uint256 limit;
        uint256 minted;
        address currency;
        uint256 price;
        address author;
    }

    struct BoxView {
        uint256 id;
        uint256 categoryId;
        string name;
        string res;
        address nft;
        uint256 limit;
        uint256 minted;
        address author;
    }

    struct LevelInfo {
        uint256 level;
        string name;
        string res;
    }

    event NewCategory(
        uint256 indexed id,
        string name,
        address nft,
        uint256 limit,
        address author,
        address currency,
        uint256 price
    );
    event OpenBox(
        uint256 indexed id,
        address indexed nft,
        uint256 boxId,
        uint256 tokenId
    );
    event Minted(uint256 indexed id, uint256 indexed categoryId, address to);

    function getLevelInfo(uint256 categoryId, uint256 level)
        external
        view
        returns (LevelInfo memory);

    function buyBox(uint256 categoryId, uint256 amount) external;

    function burnBox(uint256 tokenId) external;

    function getCategory(uint256 categoryId)
        external
        view
        returns (Category memory);

    function getBox(uint256 boxId) external view returns (BoxView memory);

    function openBox(uint256 boxId) external;

    function getCategories() external view returns (Category[] memory);

    function getCategoryLevels(uint256 categoryId)
        external
        view
        returns (LevelInfo[] memory);

    function getBoxCategory(uint256 tokenId)
        external
        view
        returns (Category memory);
}
