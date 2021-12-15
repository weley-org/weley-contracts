pragma solidity ^0.8.0;

import "../libraries/SafeDecimalMath.sol";
import "./interfaces/IWeleyToken.sol";
import "./WeleyBEP20.sol";

contract Weley is WeleyBEP20 {
    using SafeMath for uint256;
    using SafeDecimalMath for uint256;

    uint256 public teamRate;
    address public teamWallet;

    address public feeWallet;
    uint256 public vTokenFeeRate;

    uint256 public burnRate;

    mapping(address => bool) _whiteList;

    uint256 public totalBurned;

    function initialize(
        string memory name_,
        string memory symbol_,
        uint256 initialSupply_
    ) public initializer {
        __WeleyBEP20_init(name_, symbol_, initialSupply_);
        teamRate = 990;
        vTokenFeeRate = 2;
        burnRate = 3;
    }

    function setTeamRate(uint256 rate) public onlyOwner {
        require(rate < 10000, "bad rate");
        teamRate = rate;
    }

    function setTeamWallet(address team) public onlyOwner {
        teamWallet = team;
    }

    function setFeeWallet(address _feeWallet) public onlyOwner {
        feeWallet = _feeWallet;
    }

    function setVTokenFeeRate(uint256 rate) public onlyOwner {
        require(rate < 100, "bad num");

        vTokenFeeRate = rate;
    }

    function setBurnRate(uint256 rate) public onlyOwner {
        require(rate < 100, "bad num");
        burnRate = rate;
    }

    function addWhiteList(address user) public onlyOwner {
        _whiteList[user] = true;
    }

    function removeWhiteList(address user) public onlyOwner {
        delete _whiteList[user];
    }

    function isWhiteList(address user) public view returns (bool) {
        return _whiteList[user];
    }

    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal virtual override {
        uint256 _amount = amount;
        if (
            !_whiteList[sender] &&
            !_whiteList[recipient] &&
            recipient != address(0)
        ) {
            if (vTokenFeeRate > 0 && feeWallet != address(0)) {
                uint256 fee = _amount.mul(vTokenFeeRate).div(10000);
                amount = amount.sub(fee);
                super._transfer(sender, feeWallet, fee);
            }

            if (burnRate > 0) {
                uint256 burnAmount = _amount.mul(burnRate).div(10000);
                amount = amount.sub(burnAmount);
                _burn(sender, burnAmount);
            }
        }
        super._transfer(sender, recipient, amount);
    }

    function mint(address _to, uint256 _amount) public override onlyMinter {
        uint256 teamAmount;
        if (teamWallet != address(0) && teamRate > 0) {
            teamAmount = _amount.mul(teamRate).div(10000);
        }
        _mint(_to, _amount);
        if (teamAmount > 0) {
            _mint(teamWallet, teamAmount);
        }
    }

    function burn(uint256 amount) public override {
        _burn(msg.sender, amount);
        totalBurned += amount;
    }
}
