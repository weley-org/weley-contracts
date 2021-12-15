pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

abstract contract Caller is OwnableUpgradeable {
    using EnumerableSet for EnumerableSet.AddressSet;

    EnumerableSet.AddressSet private _callers;

    modifier onlyCaller() {
        require(isCaller(msg.sender), "Caller:NOT_CALLER");
        _;
    }

    function addCaller(address account)
        public
        virtual
        onlyOwner
        returns (bool)
    {
        return _addCaller(account);
    }

    function delCaller(address account)
        public
        virtual
        onlyOwner
        returns (bool)
    {
        require(account != address(0), "Caller:INVALID_ACCOUNT");
        return _callers.remove(account);
    }

    function getCallerLength() public view virtual returns (uint256) {
        return _callers.length();
    }

    function isCaller(address account) public view virtual returns (bool) {
        return _callers.contains(account);
    }

    function getCaller(uint256 index)
        public
        view
        virtual
        onlyOwner
        returns (address)
    {
        require(index <= getCallerLength() - 1, "Caller:INVALID_INDEX");
        return _callers.at(index);
    }

    function _addCaller(address account) internal virtual returns (bool) {
        require(account != address(0), "Caller: INVALID_ACCOUNT");
        return _callers.add(account);
    }

    function getCallers()
        public
        view
        virtual
        returns (address[] memory callers)
    {
        callers = new address[](_callers.length());
        for (uint256 i; i < callers.length; i++) {
            callers[i] = _callers.at(i);
        }
    }
}
