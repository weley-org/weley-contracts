pragma solidity ^0.8.0;

import "hardhat/console.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "./swap/interfaces/IWeleySwapOracle.sol";
import "./tokens/Weley.sol";
import "./tokens/VWeley.sol";
import "./libraries/SafeDecimalMath.sol";

interface TotalTVL {
    function getTotalTVL() external view returns (uint256 totalAmount);
}

contract Aggregator is OwnableUpgradeable {
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeDecimalMath for uint256;
    using SafeMath for uint256;

    uint256 private constant ONE_YEAR = 31536000;

    address public weley;
    address public weleySwapOracle;

    EnumerableSet.AddressSet private _tvlContracts;

    address public vWeley;

    function initialize(
        address weley_,
        address vWeley_,
        address weleySwapOracle_,
        address[] memory tvlContracts_
    ) public initializer {
        __Ownable_init();
        weley = weley_;
        vWeley = vWeley_;
        weleySwapOracle = weleySwapOracle_;
        for (uint256 i; i < tvlContracts_.length; i++) {
            _tvlContracts.add(tvlContracts_[i]);
        }
    }

    function setVWeley(address val) public onlyOwner {
        vWeley = val;
    }

    function getIndexView()
        public
        view
        returns (
            uint256 weleyPrice,
            uint256 totalSupply,
            uint256 totalBurned,
            uint256 totalTVL
        )
    {
        weleyPrice = IWeleySwapOracle(weleySwapOracle).consultInstantPrice(
            weley
        );
        totalSupply = Weley(weley).totalSupply();

        totalBurned = Weley(weley).totalBurned();
        for (uint256 i; i < _tvlContracts.length(); i++) {
            totalTVL += TotalTVL(_tvlContracts.at(i)).getTotalTVL();
        }
    }

    struct VWeleyView {
        uint256 vWeleyAmount;
        uint256 weleyPrice;
        uint256 weleyValue;
        uint256 myVWeleyAmount;
        uint256 myMintedVWeleyAmount;
        uint256 myCredit;
        uint256 myEarnedVWeleyAmount;
        uint256 realtimeAPR;
        uint256 vWeleyMemberCount;
        uint256 withdrawFeeRatio;
        address[] myReferrals;
        uint256 myMonthlyReferralRewards;
    }

    function getVWeleyView(address user)
        public
        view
        returns (VWeleyView memory)
    {
        VWeley instance = VWeley(vWeley);
        VWeley.StakingInfo memory info = instance.getUserInfo(user);
        VWeleyView memory vview;
        vview.weleyPrice = IWeleySwapOracle(weleySwapOracle)
            .consultInstantPrice(weley);

        uint256 weleyRatio = instance.weleyRatio();
        if (weleyRatio > 0) {
            vview.myVWeleyAmount =
                VWeley(vWeley).weleyBalanceOf(user) /
                weleyRatio;
            vview.myMintedVWeleyAmount = info.mintedWeley / weleyRatio;
        }

        vview.vWeleyAmount = instance.totalSupply();
        uint256 totalWeleyAmount = Weley(weley).balanceOf(vWeley);
        vview.weleyValue = totalWeleyAmount.multiplyDecimal(vview.weleyPrice);
        vview.withdrawFeeRatio = instance.getWeleyWithdrawFeeRatio();

        vview.myEarnedVWeleyAmount =
            vview.myVWeleyAmount -
            vview.myMintedVWeleyAmount;
        vview.vWeleyMemberCount = instance.getMemberCount();

        vview.myReferrals = instance.getReferrals(user);
        vview.myCredit = info.credit;

        uint256 oneYearWeleyRewards = _getOneYearRewards(instance);
        if (oneYearWeleyRewards > 0) {
            if (totalWeleyAmount > 0) {
                vview.realtimeAPR = oneYearWeleyRewards
                    .divideDecimal(totalWeleyAmount)
                    .mul(100);
            }

            uint256 totalStakingPower = instance.totalStakingPower();
            if (totalStakingPower > 0) {
                vview.myMonthlyReferralRewards = oneYearWeleyRewards
                    .div(12)
                    .multiplyDecimal(info.referralSP)
                    .divideDecimal(totalStakingPower);
            }
        }

        return vview;
    }

    function _getOneYearRewards(VWeley instance)
        private
        view
        returns (uint256 weleyAmount)
    {
        (
            uint256 minTime,
            uint256 minReward,
            uint256 maxTime,
            uint256 maxReward
        ) = instance.getRewardData();
        uint256 duration = maxTime.sub(minTime);
        uint256 rewards = maxReward.sub(minReward);
        if (duration > 0 && rewards > 0) {
            weleyAmount = ONE_YEAR.multiplyDecimal(rewards).div(duration);
        }
    }
}
