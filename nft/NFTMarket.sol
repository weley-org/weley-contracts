pragma solidity ^0.8.0;
import "hardhat/console.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721ReceiverUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "../swap/libraries/TransferHelper.sol";
import "../interfaces/IWOKT.sol";
import "./interfaces/IWeleyNFT.sol";
import "./interfaces/INFTMarket.sol";
import "./interfaces/IWeleyERC721.sol";

contract NFTMarket is
    IERC721ReceiverUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    OwnableUpgradeable,
    INFTMarket
{
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.UintSet;
    using SafeMath for uint256;

    uint8 public constant STATUS_OPEN = 1;
    uint8 public constant STATUS_SUCCESS = 2;
    uint8 public constant STATUS_CLOSE = 3;

    uint256 public currentItemId;

    mapping(uint256 => Item) private _items;
    EnumerableSet.UintSet private _itemIds;
    uint256 public minDurationTime;

    address public WETH;

    EnumerableSet.AddressSet private _supportedCurrencies;
    EnumerableSet.AddressSet private _supportedNFTs;
    EnumerableSet.AddressSet private _sellers;
    EnumerableSet.AddressSet private _disabledRoyalties;
    mapping(uint256 => EnumerableSet.UintSet) private _statusItemMap;

    uint256 public startBlock;

    uint256 public tipsFeeRate;
    uint256 public baseRate;
    address payable public tipsFeeWallet;

    function initialize(
        address payable wallet,
        address weth,
        uint256 startBlock_
    ) public initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        tipsFeeWallet = wallet;
        WETH = weth;
        startBlock = startBlock_;
        tipsFeeRate = 50;
        baseRate = 1000;
        minDurationTime = 5 minutes;
        currentItemId = 10000;
        _supportedCurrencies.add(WETH);
    }

    modifier validAddress(address addr) {
        require(addr != address(0));
        _;
    }

    modifier checkTime(uint256 itemId) {
        Item memory item = _items[itemId];
        require(item.status > 0 && item.startTime <= block.timestamp, "!open");
        _;
    }

    modifier mustNotSellingOut(uint256 itemId) {
        Item memory item = _items[itemId];
        require(
            item.buyer == address(0) && item.status == STATUS_OPEN,
            "sry, selling out"
        );
        _;
    }

    function addDisabledRoyalties(address nft) public onlyOwner {
        _disabledRoyalties.add(nft);
    }

    function removeDisabledRoyalties(address nft) public onlyOwner {
        _disabledRoyalties.remove(nft);
    }

    function addSupportedNFTs(address[] memory nfts) public onlyOwner {
        for (uint256 i = 0; i < nfts.length; i++) {
            _supportedNFTs.add(nfts[i]);
        }
    }

    function removeSupportedNFT(address nft)
        public
        onlyOwner
        validAddress(nft)
    {
        _supportedNFTs.remove(nft);
    }

    function addSellers(address[] memory sellers) public onlyOwner {
        for (uint256 i = 0; i < sellers.length; i++) {
            _sellers.add(sellers[i]);
        }
    }

    function removeSeller(address seller) public onlyOwner {
        _sellers.remove(seller);
    }

    function addSupportedCurrencies(address[] memory currencies)
        public
        onlyOwner
    {
        for (uint256 i; i < currencies.length; i++) {
            _supportedCurrencies.add(currencies[i]);
        }
    }

    function removeSupportedCurrency(address val) public onlyOwner {
        _supportedCurrencies.remove(val);
    }

    function setStartBlock(uint256 val) public onlyOwner {
        startBlock = val;
    }

    function setMinDurationTime(uint256 val) public onlyOwner {
        minDurationTime = val;
    }

    function setTipsFeeWallet(address payable val) public onlyOwner {
        tipsFeeWallet = val;
    }

    function getTipsFeeWallet() public view returns (address) {
        return address(tipsFeeWallet);
    }

    function getItem(uint256 itemId)
        external
        view
        override
        returns (Item memory)
    {
        return _items[itemId];
    }

    function getSalesPrice(uint256 itemId) external view returns (uint256) {
        Item memory item = _items[itemId];
        if (item.buyer != address(0) || item.status == STATUS_SUCCESS) {
            return item.finalPrice;
        } else {
            if (block.timestamp <= item.startTime) {
                return item.maxPrice;
            } else if (
                block.timestamp > item.startTime.add(item.durationTime)
            ) {
                return item.minPrice;
            } else {
                uint256 per = item.maxPrice.sub(item.minPrice).div(
                    item.durationTime
                );
                return
                    item.maxPrice.sub(
                        block.timestamp.sub(item.startTime).mul(per)
                    );
            }
        }
    }

    function setBaseRate(uint256 val) external onlyOwner {
        baseRate = val;
    }

    function setTipsFeeRate(uint256 val) external onlyOwner {
        tipsFeeRate = val;
    }

    function close(uint256 itemId)
        external
        override
        mustNotSellingOut(itemId)
        nonReentrant
        whenNotPaused
    {
        Item memory item = _items[itemId];
        require(
            item.seller == msg.sender || msg.sender == owner(),
            "author & owner"
        );
        _statusItemMap[item.status].remove(item.id);
        IWeleyERC721(item.nft).transferFrom(
            address(this),
            item.seller,
            item.tokenId
        );
        item.status = STATUS_CLOSE;
        _statusItemMap[item.status].add(item.id);
        _items[itemId] = item;
        emit Close(itemId, item.tokenId);
    }

    function open(
        address nft,
        uint256 tokenId,
        address currency,
        uint256 maxPrice,
        uint256 minPrice,
        uint256 startTime,
        uint256 durationTime
    ) external override nonReentrant whenNotPaused validAddress(nft) {
        require(tokenId != 0, "INVALID_TOKEN_ID");
        require(durationTime >= minDurationTime, "INVALID_DURATION");
        require(maxPrice >= minPrice, "INVALID_PRICE");

        require(_supportedNFTs.contains(nft), "UNSUPPORTED_NFT");
        require(
            _supportedCurrencies.contains(currency),
            "UNSUPPORTED_CURRENCY"
        );

        IWeleyERC721 erc721 = IWeleyERC721(nft);

        erc721.transferFrom(msg.sender, address(this), tokenId);
        currentItemId++;
        Item memory item;
        item.status = STATUS_OPEN;
        item.id = currentItemId;
        item.tokenId = tokenId;
        item.seller = payable(msg.sender);
        item.nft = nft;
        item.startTime = startTime;
        item.durationTime = durationTime;
        item.maxPrice = maxPrice;
        item.minPrice = minPrice;
        item.currency = currency;
        item.tokenName = erc721.getTokenName(tokenId);
        item.tokenURI = erc721.tokenURI(tokenId);
        _itemIds.add(item.id);
        _items[item.id] = item;
        _statusItemMap[item.status].add(item.id);

        emit Open(
            item.id,
            tokenId,
            msg.sender,
            nft,
            address(0x0),
            currency,
            startTime,
            durationTime,
            maxPrice,
            minPrice,
            0
        );
    }

    function buy(uint256 itemId)
        public
        payable
        override
        nonReentrant
        whenNotPaused
        mustNotSellingOut(itemId)
        checkTime(itemId)
    {
        Item memory item = _items[itemId];
        require(item.status == STATUS_OPEN, "bad status");
        _statusItemMap[item.status].remove(item.id);

        uint256 price = this.getSalesPrice(itemId);
        item.status = STATUS_SUCCESS;
        _statusItemMap[item.status].add(item.id);

        uint256 tipsFee = price.mul(tipsFeeRate).div(baseRate);
        uint256 purchase = price.sub(tipsFee);

        address currency = item.currency == address(0) ? WETH : item.currency;

        uint256 royaltiesAmount;
        bytes4 selector = bytes4(keccak256("getRoyalties(uint256)"));
        if (
            !_disabledRoyalties.contains(item.nft) &&
            IWeleyERC721(item.nft).supportsInterface(selector)
        ) {
            IWeleyNFT.Royalty[] memory fees = IWeleyNFT(item.nft).getRoyalties(
                item.tokenId
            );
            for (uint256 i = 0; i < fees.length; i++) {
                uint256 feeValue = price.mul(fees[i].value).div(10000);
                if (purchase > feeValue) {
                    purchase = purchase.sub(feeValue);
                } else {
                    feeValue = purchase;
                    purchase = 0;
                }
                if (feeValue != 0) {
                    royaltiesAmount = royaltiesAmount.add(feeValue);
                    if (WETH == currency) {
                        TransferHelper.safeTransferETH(
                            fees[i].account,
                            feeValue
                        );
                    } else {
                        IERC20(currency).transferFrom(
                            msg.sender,
                            fees[i].account,
                            feeValue
                        );
                    }
                }
            }
        }

        if (WETH == currency) {
            require(
                msg.value >= this.getSalesPrice(itemId),
                "your price is too low"
            );
            uint256 returnBack = msg.value.sub(price);
            if (returnBack > 0) {
                payable(msg.sender).transfer(returnBack);
            }
            if (tipsFee > 0) {
                IWOKT(WETH).deposit{value: tipsFee}();
                IWOKT(WETH).transfer(tipsFeeWallet, tipsFee);
            }
            item.seller.transfer(purchase);
        } else {
            IERC20(currency).transferFrom(msg.sender, tipsFeeWallet, tipsFee);
            IERC20(currency).transferFrom(msg.sender, item.seller, purchase);
        }

        IWeleyERC721(item.nft).transferFrom(
            address(this),
            msg.sender,
            item.tokenId
        );
        item.buyer = payable(msg.sender);
        item.finalPrice = price;

        _items[itemId] = item;

        emit Buy(
            itemId,
            item.tokenId,
            msg.sender,
            currency,
            price,
            tipsFee,
            royaltiesAmount,
            block.timestamp
        );
    }

    function getItems(uint8 status)
        external
        view
        override
        returns (Item[] memory items)
    {
        items = new Item[](_statusItemMap[status].length());
        for (uint256 i; i < items.length; i++) {
            items[i] = _items[_statusItemMap[STATUS_OPEN].at(i)];
        }
    }

    function getSupportedCurrencies()
        external
        view
        override
        returns (address[] memory currencies)
    {
        currencies = new address[](_supportedCurrencies.length());
        for (uint256 i; i < currencies.length; i++) {
            currencies[i] = _supportedCurrencies.at(i);
        }
    }

    function getSupportedNFTs()
        external
        view
        override
        returns (address[] memory nfts)
    {
        nfts = new address[](_supportedNFTs.length());
        for (uint256 i; i < nfts.length; i++) {
            nfts[i] = _supportedNFTs.at(i);
        }
    }

    function getSellers()
        external
        view
        override
        returns (address[] memory sellers)
    {
        sellers = new address[](_sellers.length());
        for (uint256 i; i < sellers.length; i++) {
            sellers[i] = _sellers.at(i);
        }
    }

    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes memory data
    ) public override returns (bytes4) {
        if (address(this) != operator) {
            return 0;
        }
        emit NFTReceived(operator, from, tokenId, data);
        return
            bytes4(
                keccak256("onERC721Received(address,address,uint256,bytes)")
            );
    }
}
