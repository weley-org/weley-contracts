pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import "../abstracts/Minter.sol";
import "./interfaces/IWeleyERC721.sol";

abstract contract WeleyERC721 is
    IWeleyERC721,
    ERC721EnumerableUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    Minter
{
    function __WeleyERC721_init(string memory name_, string memory symbol_)
        public
        virtual
        initializer
    {
        __Ownable_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        __ERC721_init(name_, symbol_);
    }

    function mint(address to, uint256 tokenId)
        public
        virtual
        override
        onlyMinter
    {
        _mint(to, tokenId);
    }

    function burn(uint256 tokenId) public virtual override {
        address owner = ownerOf(tokenId);
        require(_msgSender() == owner, "caller is not the token owner");
        _burn(tokenId);
    }

    function tokensOfOwner(address owner)
        public
        view
        override
        returns (uint256[] memory tokenIds)
    {
        uint256 balance = balanceOf(owner);
        tokenIds = new uint256[](balance);
        for (uint256 i; i < balance; i++) {
            tokenIds[i] = tokenOfOwnerByIndex(owner, i);
        }
    }
}
