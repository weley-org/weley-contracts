pragma solidity ^0.8.0;

import "./WeleyBEP20.sol";

contract MockToken is WeleyBEP20 {
    function initialize(
        string memory name_,
        string memory symbol_,
        uint256 initialSupply_
    ) public initializer {
        __WeleyBEP20_init(name_, symbol_, initialSupply_);
    }
}
