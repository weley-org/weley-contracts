pragma solidity ^0.8.0;
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "../libraries/Random.sol";
import "../tokens/interfaces/IWeleyBEP20.sol";
import "./interfaces/IWeleyERC721.sol";
import "./interfaces/IWeleyNFT.sol";
import "./WeleyERC721.sol";

contract WeleyNFT is WeleyERC721, IWeleyNFT {
    using SafeMath for uint256;
    using EnumerableSet for EnumerableSet.AddressSet;
    using Strings for uint256;

    event Minted(
        uint256 indexed id,
        address to,
        uint256 level,
        uint256 power,
        string name,
        string res,
        address author,
        uint256 timestamp
    );
    event Upgraded(
        uint256 indexed nft1Id,
        uint256 nft2Id,
        uint256 newNFTId,
        uint256 newLevel,
        uint256 timestamp
    );
    event RoyaltiesUpdated(
        uint256 indexed nftId,
        uint256 oldRoyalties,
        uint256 newRoyalties
    );

    mapping(uint256 => TokenInfo) private _nfts;

    bytes4 private constant _INTERFACE_ID_GET_ROYALTIES = 0xbb3bafd6;
    bytes4 private constant _INTERFACE_ID_ROYALTIES = 0xb282e1fc;

    uint256 public constant maxLevel = 6;
    uint256 private tokenId;
    string public baseURI;
    address public override feeToken;
    address public feeWallet;

    uint256[] public levelBasePower;
    uint256[] public levelUpFee;

    mapping(uint256 => Royalty[]) private _royalties;

    bool public canUpgrade;

    uint256 public override totalPower;

    function initialize(
        string memory name_,
        string memory symbol_,
        address feeToken_,
        address feeWallet_,
        bool _canUpgrade,
        string memory baseURI_
    ) public initializer {
        __WeleyERC721_init(name_, symbol_);
        _addMinter(msg.sender);
        supportsInterface(_INTERFACE_ID_GET_ROYALTIES);
        supportsInterface(_INTERFACE_ID_ROYALTIES);
        feeToken = feeToken_;
        feeWallet = feeWallet_;
        baseURI = baseURI_;
        canUpgrade = _canUpgrade;
        tokenId = 1000;
        levelBasePower = [1000, 2500, 6500, 14500, 35000, 90000];
        levelUpFee = [0, 500e18, 1200e18, 2400e18, 4800e18, 9600e18];
    }

    function setFeeWallet(address val) public onlyOwner {
        feeWallet = val;
    }

    function setFeeToken(address val) public onlyOwner {
        feeToken = val;
    }

    function setCanUpgrade(bool newVal) public onlyOwner {
        canUpgrade = newVal;
    }

    function getNFT(uint256 id)
        public
        view
        override
        returns (TokenInfo memory)
    {
        return _nfts[id];
    }

    function setDefaultRoyalty(address payable account, uint96 value)
        public
        onlyOwner
    {
        uint256 old = sumRoyalties(0);
        if (_royalties[0].length > 0) {
            _royalties[0][0] = Royalty(account, value);
        } else {
            _royalties[0].push(Royalty(account, value));
        }

        emit RoyaltiesUpdated(0, old, sumRoyalties(0));
    }

    function getDefultRoyalty() public view returns (Royalty memory part) {
        if (_royalties[0].length > 0) {
            part = _royalties[0][0];
        }
    }

    function getRoyalties(uint256 tokenId_)
        public
        view
        override
        returns (Royalty[] memory)
    {
        Royalty[] memory ret = _royalties[tokenId_];
        if (ret.length == 0) {
            return _royalties[0];
        }
        return ret;
    }

    function sumRoyalties(uint256 tokenId_)
        public
        view
        override
        returns (uint256)
    {
        uint256 val;
        Royalty[] memory parts = getRoyalties(tokenId_);
        for (uint256 i = 0; i < parts.length; i++) {
            val += parts[i].value;
        }
        return val;
    }

    function updateRoyalties(uint256 tokenId_, Royalty[] memory parts) public {
        require(_nfts[tokenId_].author == msg.sender, "not the author");
        uint256 old = sumRoyalties(tokenId_);
        delete _royalties[tokenId_];
        for (uint256 i = 0; i < parts.length; i++) {
            _royalties[tokenId_].push(parts[i]);
        }
        emit RoyaltiesUpdated(tokenId_, old, sumRoyalties(tokenId_));
    }

    function updateRoyalty(
        uint256 tokenId_,
        uint256 index,
        Royalty memory newPart
    ) public {
        require(_nfts[tokenId_].author == msg.sender, "not the author");
        require(index < _royalties[tokenId_].length, "bad index");
        uint256 old = sumRoyalties(tokenId_);
        _royalties[tokenId_][index] = newPart;
        emit RoyaltiesUpdated(tokenId_, old, sumRoyalties(tokenId_));
    }

    function addRoyalty(uint256 tokenId_, Royalty memory newPart) public {
        require(_nfts[tokenId_].author == msg.sender, "not the author");
        uint256 old = sumRoyalties(tokenId_);
        _royalties[tokenId_].push(newPart);
        emit RoyaltiesUpdated(tokenId_, old, sumRoyalties(tokenId_));
    }

    function _doMint(
        address to,
        string memory nftName,
        uint256 level,
        uint256 power,
        string memory res,
        address author
    ) internal returns (uint256) {
        tokenId++;
        if (bytes(nftName).length == 0) {
            nftName = name();
        }

        _mint(to, tokenId);

        TokenInfo memory nft;
        nft.tokenId = tokenId;
        nft.name = nftName;
        nft.level = level;
        nft.power = power;
        nft.res = res;
        nft.author = author;
        _nfts[tokenId] = nft;

        totalPower = totalPower.add(power);

        emit Minted(
            tokenId,
            to,
            level,
            power,
            nftName,
            res,
            author,
            block.timestamp
        );
        return tokenId;
    }

    function tokenURI(uint256 id) public view override returns (string memory) {
        return getTokenInfo(id).res;
    }

    function getTokenName(uint256 id)
        public
        view
        override
        returns (string memory)
    {
        return getTokenInfo(id).name;
    }

    function getTokenInfo(uint256 id)
        public
        view
        override
        returns (TokenInfo memory)
    {
        return _nfts[id];
    }

    function getTokenInfos(uint256[] memory ids)
        external
        view
        override
        returns (TokenInfo[] memory)
    {
        TokenInfo[] memory infos = new TokenInfo[](ids.length);
        for (uint256 i = 0; i < ids.length; i++) {
            infos[i] = _nfts[ids[i]];
        }
        return infos;
    }

    function mintNFT(
        address to,
        string memory nftName,
        uint256 level,
        uint256 power,
        string memory res,
        address author
    ) public override onlyMinter nonReentrant returns (uint256) {
        return _doMint(to, nftName, level, power, res, author);
    }

    function randomPower(uint256 level, uint256 seed)
        internal
        view
        returns (uint256)
    {
        if (level == 1) {
            return levelBasePower[0] + (seed % 200);
        } else if (level == 2) {
            return levelBasePower[1] + (seed % 500);
        } else if (level == 3) {
            return levelBasePower[2] + (seed % 500);
        } else if (level == 4) {
            return levelBasePower[3] + (seed % 500);
        } else if (level == 5) {
            return levelBasePower[4] + (seed % 5000);
        }
        return levelBasePower[5] + (seed % 10000);
    }

    function getUpgradeFee(uint256 newLevel)
        public
        view
        override
        returns (uint256)
    {
        return levelUpFee[newLevel - 1];
    }

    function upgradeNFT(uint256 nftId, uint256 materialNFTId)
        public
        override
        nonReentrant
        whenNotPaused
    {
        require(canUpgrade, "CANT UPGRADE");
        TokenInfo memory nft = getNFT(nftId);
        TokenInfo memory materialNFT = getNFT(materialNFTId);

        require(nft.level == materialNFT.level, "The level must be the same");
        require(nft.level < maxLevel, "Has reached the max level");

        burn(nftId);
        burn(materialNFTId);
        uint256 burnedPower = nft.power.add(materialNFT.power);
        totalPower = totalPower > burnedPower ? totalPower.sub(burnedPower) : 0;

        uint256 newLevel = nft.level + 1;
        uint256 fee = getUpgradeFee(newLevel);
        if (fee > 0) {
            IWeleyBEP20(feeToken).transferFrom(_msgSender(), feeWallet, fee);
        }

        uint256 seed = Random.computerSeed() / 23;

        uint256 newPower = randomPower(newLevel, seed);
        uint256 newId = _doMint(
            _msgSender(),
            nft.name,
            newLevel,
            newPower,
            nft.res,
            nft.author
        );

        emit Upgraded(nftId, materialNFTId, newId, newLevel, block.timestamp);
    }

    function getPower(uint256 tokenId_) public view override returns (uint256) {
        return _nfts[tokenId_].power;
    }

    function getLevel(uint256 tokenId_) public view override returns (uint256) {
        return _nfts[tokenId_].level;
    }

    function tokenInfosOfOwner(address owner)
        external
        view
        override
        returns (TokenInfo[] memory)
    {
        uint256[] memory tokenIds = tokensOfOwner(owner);
        TokenInfo[] memory tokens = new TokenInfo[](tokenIds.length);
        for (uint256 i; i < tokenIds.length; i++) {
            tokens[i] = _nfts[tokenIds[i]];
        }
        return tokens;
    }
}
