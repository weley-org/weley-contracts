pragma solidity ^0.8.0;

import "hardhat/console.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "../libraries/SafeDecimalMath.sol";
import "../swap/interfaces/IWeleySwapOracle.sol";
import "../tokens/interfaces/IBEP20.sol";
import "./interfaces/ISinglePoolFactory.sol";
import "./SinglePool.sol";

contract SinglePoolFactory is
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    ISinglePoolFactory
{
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeMath for uint256;
    using SafeDecimalMath for uint256;

    uint256 public constant ONE_YEAR = 31536000;

    EnumerableSet.AddressSet private pools;

    address public weleySwapOracle;

    function initialize(address weleySwapOracle_) public initializer {
        __Ownable_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        weleySwapOracle = weleySwapOracle_;
    }

    function setWeleySwapOracle(address val) external onlyOwner {
        weleySwapOracle = val;
    }

    function registerPool(address pool) public onlyOwner {
        pools.add(pool);
    }

    function revokePool(address pool) public onlyOwner {
        pools.remove(pool);
    }

    function getPools() public view override returns (address[] memory) {
        address[] memory result = new address[](pools.length());
        for (uint256 i = 0; i < result.length; i++) {
            result[i] = pools.at(i);
        }
        return result;
    }

    function getAllPoolViews()
        public
        view
        override
        returns (PoolView[] memory)
    {
        uint256 len = pools.length();
        PoolView[] memory views = new PoolView[](len);
        for (uint256 i = 0; i < len; i++) {
            views[i] = getPoolViewByIndex(i);
        }
        return views;
    }

    function getTotalTVL() public view override returns (uint256 totalAmount) {
        for (uint256 i = 0; i < pools.length(); i++) {
            SinglePool pool = SinglePool(pools.at(i));
            totalAmount += _getTVL(pool.depositToken(), pool.totalDeposit());
        }
    }

    function getPoolViewByAddress(address poolAddress)
        public
        view
        override
        returns (PoolView memory)
    {
        SinglePool pool = SinglePool(poolAddress);
        console.log("SinglePoolFactory,poolAddress", poolAddress);
        console.log(
            "SinglePoolFactory,pool.depositToken()",
            pool.depositToken()
        );
        console.log("SinglePoolFactory,pool.rewardToken()", pool.rewardToken());

        IBEP20 depositToken = IBEP20(pool.depositToken());
        IBEP20 rewardToken = IBEP20(pool.rewardToken());

        uint256 depositAmount = pool.totalDeposit();
        uint256 rewardPerBlock = pool.rewardPerBlock();
        return
            PoolView({
                pool: poolAddress,
                depositToken: address(depositToken),
                rewardsToken: address(rewardToken),
                lastRewardBlock: pool.lastRewardBlock(),
                accRewardPerShare: pool.accRewardsPerShare(),
                rewardsPerBlock: rewardPerBlock,
                totalAmount: depositAmount,
                bonusStartBlock: pool.bonusStartBlock(),
                bonusEndBlock: pool.bonusEndBlock(),
                depositSymbol: depositToken.symbol(),
                depositName: depositToken.name(),
                rewardsSymbol: rewardToken.symbol(),
                rewardsName: rewardToken.name(),
                tvl: int256(_getTVL(address(depositToken), depositAmount)),
                apr: int256(
                    _getAPR(
                        address(depositToken),
                        depositAmount,
                        address(rewardToken),
                        rewardPerBlock
                    )
                )
            });
    }

    function _getTVL(address depositToken, uint256 depositAmount)
        internal
        view
        returns (uint256)
    {
        uint256 price = IWeleySwapOracle(weleySwapOracle).consultInstantPrice(
            depositToken
        );
        if (price > 0) {
            return depositAmount.multiplyDecimal(uint256(price));
        }
        return 0;
    }

    function _getAPR(
        address depositToken,
        uint256 depositAmount,
        address rewardToken,
        uint256 rewardsPerBlock
    ) internal view returns (uint256) {
        uint256 tvl = _getTVL(depositToken, depositAmount);
        if (tvl == 0) {
            console.log("SinglePoolFactory,invalid tvl");
            return 0;
        }
        uint256 rewardTokenPrice = IWeleySwapOracle(weleySwapOracle)
            .consultInstantPrice(address(rewardToken));
        if (rewardTokenPrice <= 0) {
            console.log("SinglePoolFactory,invalid rewardTokenPrice");
            return 0;
        }
        uint256 blockSpeed = IWeleySwapOracle(weleySwapOracle).getBlockSpeed();
        uint256 yearlyRewards = (ONE_YEAR * 1000)
            .div(blockSpeed)
            .mul(rewardsPerBlock)
            .multiplyDecimal(rewardTokenPrice);
        return yearlyRewards.divideDecimal(tvl).mul(100);
    }

    function getPoolViewByIndex(uint256 index)
        public
        view
        override
        returns (PoolView memory)
    {
        return getPoolViewByAddress(pools.at(index));
    }

    function getUserView(address poolAddress, address account)
        public
        view
        override
        returns (UserView memory)
    {
        SinglePool pool = SinglePool(poolAddress);
        (uint256 amount, ) = pool.userInfoMap(account);
        return
            UserView({
                stakedAmount: amount,
                pendingReward: pool.pendingReward(account),
                tokenBalance: IBEP20(pool.depositToken()).balanceOf(account)
            });
    }

    function getUserViews(address account)
        external
        view
        override
        returns (UserView[] memory)
    {
        uint256 len = pools.length();
        UserView[] memory views = new UserView[](len);
        for (uint256 i = 0; i < len; i++) {
            views[i] = getUserView(pools.at(i), account);
        }
        return views;
    }
}
