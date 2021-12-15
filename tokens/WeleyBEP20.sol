pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721ReceiverUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "./interfaces/IWeleyBEP20.sol";
import "../abstracts/Minter.sol";

abstract contract WeleyBEP20 is
    IWeleyBEP20,
    ERC20Upgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    Minter
{
    function __WeleyBEP20_init(
        string memory name_,
        string memory symbol_,
        uint256 initialSupply_
    ) public virtual initializer {
        __ERC20_init(name_, symbol_);
        __Ownable_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        if (initialSupply_ > 0) {
            _mint(msg.sender, initialSupply_);
        }
    }

    function getOwner() external view override returns (address) {
        return owner();
    }

    function mint(address _to, uint256 _amount)
        public
        virtual
        override
        onlyMinter
    {
        _mint(_to, _amount);
    }

    function burn(uint256 amount) public virtual override {
        _burn(msg.sender, amount);
    }
}
