pragma solidity ^0.8.0;

interface INFTMarket {
    struct Item {
        uint256 id;
        address nft;
        uint256 tokenId;
        address currency;
        uint256 startTime;
        uint256 durationTime;
        uint256 maxPrice;
        uint256 minPrice;
        uint256 finalPrice;
        uint8 status;
        address payable seller;
        address payable buyer;
        string tokenName;
        string tokenURI;
    }

    event Buy(
        uint256 indexed id,
        uint256 indexed tokenId,
        address buyer,
        address currency,
        uint256 finalPrice,
        uint256 tipsFee,
        uint256 royaltiesAmount,
        uint256 timestamp
    );
    event Open(
        uint256 indexed id,
        uint256 indexed tokenId,
        address seller,
        address nft,
        address buyer,
        address currency,
        uint256 startTime,
        uint256 durationTime,
        uint256 maxPrice,
        uint256 minPrice,
        uint256 finalPrice
    );
    event Close(uint256 indexed id, uint256 tokenId);
    event NFTReceived(
        address operator,
        address from,
        uint256 tokenId,
        bytes data
    );

    function getItems(uint8 status) external view returns (Item[] memory);

    function open(
        address nft,
        uint256 tokenId,
        address currency,
        uint256 maxPrice,
        uint256 minPrice,
        uint256 startTime,
        uint256 durationTime
    ) external;

    function buy(uint256 itemId) external payable;

    function close(uint256 itemId) external;

    function getItem(uint256 itemId) external view returns (Item memory);

    function getSupportedCurrencies()
        external
        view
        returns (address[] memory currencies);

    function getSupportedNFTs() external view returns (address[] memory nfts);

    function getSellers() external view returns (address[] memory sellers);
}
