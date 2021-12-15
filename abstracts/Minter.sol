pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

abstract contract Minter is OwnableUpgradeable {
    using EnumerableSet for EnumerableSet.AddressSet;

    EnumerableSet.AddressSet private _minters;

    modifier onlyMinter() {
        require(isMinter(msg.sender), "Minter:NOT_MINTER");
        _;
    }

    function addMinter(address account)
        public
        virtual
        onlyOwner
        returns (bool)
    {
        return _addMinter(account);
    }

    function delMinter(address account)
        public
        virtual
        onlyOwner
        returns (bool)
    {
        require(account != address(0), "Minter:INVALID_ACCOUNT");
        return _minters.remove(account);
    }

    function getMinterLength() public view virtual returns (uint256) {
        return _minters.length();
    }

    function isMinter(address account) public view virtual returns (bool) {
        return _minters.contains(account);
    }

    function getMinter(uint256 index)
        public
        view
        virtual
        onlyOwner
        returns (address)
    {
        require(index <= getMinterLength() - 1, "Minter:INVALID_INDEX");
        return _minters.at(index);
    }

    function _addMinter(address account) internal virtual returns (bool) {
        require(account != address(0), "Minter: INVALID_ACCOUNT");
        return _minters.add(account);
    }
}
