pragma solidity ^0.8.0;

import "hardhat/console.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "../libraries/Random.sol";
import "../tokens/interfaces/IWeleyBEP20.sol";
import "./interfaces/IWeleyNFT.sol";
import "./WeleyERC721.sol";
import "../libraries/SafeDecimalMath.sol";
import "./interfaces/IMysteryBox.sol";

contract MysteryBox is WeleyERC721, IMysteryBox {
    using EnumerableSet for EnumerableSet.UintSet;
    using SafeMath for uint256;
    using SafeDecimalMath for uint256;
    using Strings for uint256;

    uint256 private _boxId;

    mapping(uint256 => uint256) private _boxCategoryIdMap;

    mapping(uint256 => Category) private _categoryMap;
    EnumerableSet.UintSet private _categoryIds;

    mapping(uint256 => mapping(uint256 => LevelInfo))
        private _categoryLevelInfoMap;

    mapping(uint256 => EnumerableSet.UintSet) private _categoryLevels;

    uint256[] private _levelBasePower;

    function initialize(string memory name_, string memory symbol_)
        public
        initializer
    {
        __WeleyERC721_init(name_, symbol_);
        _levelBasePower = [1000, 2500, 6500, 14500, 35000, 90000];
        _boxId = 1000;
    }

    function registerCategory(
        uint256 categoryId,
        string memory name_,
        string memory res_,
        address nft,
        uint256 limit,
        address author,
        address currency,
        uint256 price
    ) public onlyOwner {
        require(
            !_categoryIds.contains(categoryId),
            "MysteryBox: CATEGORY_ID_EXISTS"
        );
        _categoryMap[categoryId] = Category({
            id: categoryId,
            name: name_,
            res: res_,
            minted: 0,
            nft: nft,
            limit: limit,
            author: author,
            currency: currency,
            price: price
        });
        _categoryIds.add(categoryId);
        emit NewCategory(
            categoryId,
            name_,
            nft,
            limit,
            author,
            currency,
            price
        );
    }

    function getCategories()
        external
        view
        override
        returns (Category[] memory)
    {
        Category[] memory categories = new Category[](_categoryIds.length());
        for (uint256 i; i < categories.length; i++) {
            categories[i] = _categoryMap[_categoryIds.at(i)];
        }
        return categories;
    }

    function setLevels(
        uint256 categoryId,
        uint256[] memory levels,
        string[] memory names,
        string[] memory resources
    ) public onlyOwner {
        console.log("setLevels");
        for (uint256 i = 0; i < levels.length; i++) {
            uint256 level = levels[i];
            _categoryLevelInfoMap[categoryId][level] = LevelInfo(
                level,
                names[i],
                resources[i]
            );
            _categoryLevels[categoryId].add(level);
            console.log("level", level);
        }
    }

    function getBoxCategory(uint256 tokenId)
        public
        view
        override
        returns (Category memory)
    {
        require(_exists(tokenId), "MysteryBox: TOKEN_NON_EXISTENT");
        return _categoryMap[_boxCategoryIdMap[tokenId]];
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override
        returns (string memory)
    {
        return getBoxCategory(tokenId).res;
    }

    function getTokenName(uint256 tokenId)
        public
        view
        override
        returns (string memory)
    {
        return getBoxCategory(tokenId).name;
    }

    function setLevel(
        uint256 categoryId,
        uint256 level,
        string memory name,
        string memory res
    ) public onlyOwner {
        _categoryLevelInfoMap[categoryId][level] = LevelInfo(level, name, res);
    }

    function getCategoryLevels(uint256 categoryId)
        external
        view
        override
        returns (LevelInfo[] memory)
    {
        LevelInfo[] memory levels = new LevelInfo[](
            _categoryLevels[categoryId].length()
        );
        for (uint256 i; i < levels.length; i++) {
            uint256 level = _categoryLevels[categoryId].at(i);
            console.log("level", level);
            levels[i] = _categoryLevelInfoMap[categoryId][level];
        }
        return levels;
    }

    function mintBox(
        uint256 categoryId,
        uint256 amount,
        address to
    ) public onlyOwner {
        _mintTo(categoryId, amount, to);
    }

    function getLevelInfo(uint256 categoryId, uint256 level)
        external
        view
        override
        returns (LevelInfo memory)
    {
        return _categoryLevelInfoMap[categoryId][level];
    }

    function buyBox(uint256 categoryId, uint256 amount)
        external
        override
        whenNotPaused
        nonReentrant
    {
        _mintTo(categoryId, amount, msg.sender);

        Category memory box = _categoryMap[categoryId];

        IWeleyBEP20 token = IWeleyBEP20(box.currency);

        uint256 tokenAmount = box.price.mul(amount);
        require(
            token.balanceOf(msg.sender) >= tokenAmount,
            "MysterBox: INSUFICIENT_BALANCE"
        );
        require(
            token.allowance(msg.sender, address(this)) >= tokenAmount,
            "MysterBox: INSUFICIENT_ALLOWANCE"
        );
        token.transferFrom(msg.sender, address(this), tokenAmount);
        token.burn(tokenAmount);
    }

    function burnBox(uint256 tokenId)
        public
        override
        whenNotPaused
        nonReentrant
    {
        address owner = ownerOf(tokenId);
        require(_msgSender() == owner, "MysterBox: NOT_OWNER");
        delete _boxCategoryIdMap[tokenId];
        _burn(tokenId);
    }

    function getCategory(uint256 categoryId)
        external
        view
        override
        returns (Category memory)
    {
        return _categoryMap[categoryId];
    }

    function getBox(uint256 boxId)
        external
        view
        override
        returns (BoxView memory)
    {
        uint256 categoryId = _boxCategoryIdMap[boxId];
        Category memory category = _categoryMap[categoryId];
        return
            BoxView({
                id: boxId,
                res: category.res,
                categoryId: categoryId,
                name: category.name,
                nft: category.nft,
                limit: category.limit,
                minted: category.minted,
                author: category.author
            });
    }

    function openBox(uint256 boxId) external override whenNotPaused {
        burn(boxId);
        uint256 categoryId = _boxCategoryIdMap[boxId];
        Category memory category = _categoryMap[categoryId];
        uint256 seed = Random.computerSeed();
        uint256 level = _getLevel(seed);
        uint256 power = _randomPower(level, seed);
        LevelInfo memory levelInfo = _categoryLevelInfoMap[categoryId][level];
        uint256 tokenId = IWeleyNFT(category.nft).mintNFT(
            msg.sender,
            levelInfo.name,
            level,
            power,
            levelInfo.res,
            category.author
        );
        emit OpenBox(boxId, address(category.nft), boxId, tokenId);
    }

    function _isContract(address addr) private view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(addr)
        }
        return size > 0;
    }

    function _mintTo(
        uint256 categoryId,
        uint256 amount,
        address to
    ) private {
        Category memory category = _categoryMap[categoryId];
        require(category.nft != address(0), "box not found");
        uint256 minted = category.minted.add(amount);
        if (category.limit > 0) {
            require(minted <= category.limit, "Over the limit");
        }
        _categoryMap[categoryId].minted = minted;
        for (uint256 i = 0; i < amount; i++) {
            _boxId++;
            _mint(to, _boxId);
            _boxCategoryIdMap[_boxId] = categoryId;
            emit Minted(_boxId, categoryId, to);
        }
    }

    function _randomPower(uint256 level, uint256 seed)
        private
        view
        returns (uint256)
    {
        if (level == 1) {
            return _levelBasePower[0] + (seed % 200);
        } else if (level == 2) {
            return _levelBasePower[1] + (seed % 500);
        } else if (level == 3) {
            return _levelBasePower[2] + (seed % 500);
        } else if (level == 4) {
            return _levelBasePower[3] + (seed % 500);
        } else if (level == 5) {
            return _levelBasePower[4] + (seed % 5000);
        }

        return _levelBasePower[5] + (seed % 10000);
    }

    function _getLevel(uint256 seed) private pure returns (uint256) {
        uint256 val = (seed / 8897) % 10000;
        if (val <= 8192) {
            return 1;
        } else if (val < 9415) {
            return 2;
        } else if (val < 9765) {
            return 3;
        } else if (val < 9915) {
            return 4;
        } else if (val < 9975) {
            return 5;
        }
        return 6;
    }
}
