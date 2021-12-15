pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "../tokens/interfaces/IVWeley.sol";

contract VWeleyReserve is
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable
{
    address public weley;
    address public vWeley;

    function initialize(address weley_, address vWeley_) public initializer {
        __Ownable_init();
        weley = weley_;
        vWeley = vWeley_;
    }

    function setVWeley(address val) public onlyOwner {
        vWeley = val;
    }

    function setWeley(address val) public onlyOwner {
        weley = val;
    }

    function donateToVWeley(uint256 amount) public onlyOwner {
        IERC20(weley).approve(vWeley, type(uint256).max);
        IVWeley(vWeley).donate(amount);
    }

    function donateAllToVWeley() public onlyOwner {
        uint256 amount = IERC20(weley).balanceOf(address(this));
        require(amount > 0, "Insufficient balance");

        donateToVWeley(amount);
    }

    function redeem(uint256 vWeleyAmount, bool all) public onlyOwner {
        IVWeley(vWeley).doRedeem(vWeleyAmount, all);
    }

    function weleyBalance() public view returns (uint256) {
        return IERC20(weley).balanceOf(address(this));
    }

    function vWeleyBalance() public view returns (uint256) {
        return IVWeley(vWeley).balanceOf(address(this));
    }
}
