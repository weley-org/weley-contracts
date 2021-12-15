pragma solidity ^0.8.0;

import "hardhat/console.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "../libraries/SafeDecimalMath.sol";
import "../tokens/interfaces/IWeleyBEP20.sol";
import "../swap/interfaces/IWeleySwapPair.sol";
import "../swap/interfaces/IWeleySwapObserver.sol";
import "../swap/interfaces/IWeleySwapOracle.sol";
import "./interfaces/ITradingPool.sol";
import "../swap/interfaces/IWeleySwapOracle.sol";

contract TradingPool is
    OwnableUpgradeable,
    PausableUpgradeable,
    ITradingPool,
    IWeleySwapObserver
{
    using SafeMath for uint256;
    using SafeDecimalMath for uint256;
    using EnumerableSet for EnumerableSet.AddressSet;

    uint256 public constant ONE_YEAR = 31536000;

    EnumerableSet.AddressSet private _pairs;

    IWeleyBEP20 public rewardToken;
    IWeleySwapOracle public weleySwapOracle;
    PoolInfo[] public pools;

    mapping(uint256 => mapping(address => UserInfo)) public poolUsers;

    mapping(address => uint256) public pairPoolIdMap;

    address public caller;

    uint256 public rewardTokenPerBlock;

    uint256 public totalAllocPoint;
    uint256 public totalSwapAmount;

    uint256 public startBlock;
    uint256 public halvingPeriod;

    EnumerableSet.AddressSet private _swapPairs;

    mapping(address => mapping(address => address)) public tokenPairs;

    address public dominationToken;

    modifier onlyCaller() {
        require(msg.sender == caller, "TradingPool: caller is not the caller");
        _;
    }

    function initialize(
        address rewardToken_,
        address weleySwapOracle_,
        address caller_,
        uint256 rewardTokenPerBlock_,
        uint256 startBlock_
    ) public initializer {
        __Ownable_init();
        __Pausable_init();
        rewardToken = IWeleyBEP20(rewardToken_);
        weleySwapOracle = IWeleySwapOracle(weleySwapOracle_);
        caller = caller_;
        rewardTokenPerBlock = rewardTokenPerBlock_;
        startBlock = startBlock_;
        halvingPeriod = 3952800;
    }

    function setDominationToken(address value) public onlyOwner {
        dominationToken = value;
    }

    function setRewardTokenPerBlock(uint256 val) public onlyOwner {
        _updateAllPools();
        rewardTokenPerBlock = val;
    }

    function setHalvingPeriod(uint256 val) public onlyOwner {
        halvingPeriod = val;
    }

    function setCaller(address val) public onlyOwner {
        require(
            val != address(0),
            "TradingPool: new caller is the zero address"
        );
        caller = val;
    }

    function setWeleySwapOracle(address val) public onlyOwner {
        require(val != address(0), "TradingPool:INVALID_ADDRESS");
        weleySwapOracle = IWeleySwapOracle(val);
    }

    function registerPairs(address[] memory pairs, uint256[] memory allocPoints)
        public
        onlyOwner
    {
        _updateAllPools();
        for (uint256 i; i < pairs.length; i++) {
            _registerPair(pairs[i], allocPoints[i]);
        }
    }

    function updateAllocPoint(
        uint256 poolId,
        uint256 allocPoint,
        bool withUpdate
    ) public onlyOwner {
        require(poolId < pools.length, "overflow");

        if (withUpdate) {
            _updateAllPools();
        }
        totalAllocPoint = totalAllocPoint.sub(pools[poolId].allocPoint).add(
            allocPoint
        );
        pools[poolId].allocPoint = allocPoint;
    }

    function onSwap(
        address trader,
        address tokenIn,
        address tokenOut,
        uint256 tokenAmountOut
    ) external override onlyCaller {
        if (paused()) {
            return;
        }
        console.log("TradingPool.onSwap,trader", trader);
        console.log("TradingPool.onSwap,tokenIn", tokenIn);
        console.log("TradingPool.onSwap,tokenOut", tokenOut);
        console.log("TradingPool.onSwap,tokenAmountOut", tokenAmountOut);
        address pair = tokenPairs[tokenIn][tokenOut];
        if (pair != address(0)) {
            uint256 poolId = pairPoolIdMap[pair];
            PoolInfo memory pool = pools[poolId];
            if (pool.allocPoint > 0) {
                uint256 swapAmount = weleySwapOracle.consultInstantAmountOut(
                    tokenOut,
                    dominationToken,
                    tokenAmountOut
                );
                console.log("TradingPool.onSwap,swapAmount", swapAmount);
                if (swapAmount > 0) {
                    weleySwapOracle.updatePrice(tokenOut, dominationToken);
                    _updatePool(poolId);
                    UserInfo memory user = poolUsers[poolId][trader];
                    if (user.swapAmount > 0) {
                        uint256 pendingReward = user
                            .swapAmount
                            .multiplyDecimal(pool.accRewardPerShare)
                            .sub(user.rewardDebt);
                        if (pendingReward > 0) {
                            user.pendingReward = user.pendingReward.add(
                                pendingReward
                            );
                        }
                    }
                    pool.swapAmount = pool.swapAmount.add(swapAmount);
                    pool.accSwapAmount = pool.accSwapAmount.add(swapAmount);

                    user.swapAmount = user.swapAmount.add(swapAmount);
                    user.accSwapAmount = user.accSwapAmount.add(swapAmount);
                    user.rewardDebt = user.swapAmount.multiplyDecimal(
                        pool.accRewardPerShare
                    );

                    totalSwapAmount = totalSwapAmount.add(swapAmount);

                    pools[poolId] = pool;
                    poolUsers[poolId][trader] = user;
                    emit Swap(trader, poolId, swapAmount);
                }
            }
        }
    }

    function pendingRewards(uint256 poolId, address user_)
        public
        view
        override
        returns (uint256)
    {
        require(poolId < pools.length, "TradingPool: Can not find this pool");
        PoolInfo memory pool = pools[poolId];
        UserInfo memory user = poolUsers[poolId][user_];
        uint256 accRewardPerShare = pool.accRewardPerShare;
        if (user.swapAmount > 0) {
            if (block.number > pool.lastRewardBlock) {
                uint256 blockReward = _getRewardTokenBlockReward(
                    pool.lastRewardBlock
                );
                uint256 tokenReward = blockReward.mul(pool.allocPoint).div(
                    totalAllocPoint
                );
                accRewardPerShare = accRewardPerShare.add(
                    tokenReward.divideDecimal(pool.swapAmount)
                );
                return
                    user.pendingReward.add(
                        user.swapAmount.multiplyDecimal(accRewardPerShare).sub(
                            user.rewardDebt
                        )
                    );
            }
            if (block.number == pool.lastRewardBlock) {
                return
                    user.pendingReward.add(
                        user.swapAmount.multiplyDecimal(accRewardPerShare).sub(
                            user.rewardDebt
                        )
                    );
            }
        }
        return 0;
    }

    function harvest(uint256 poolId) external override whenNotPaused {
        _harvest(poolId);
    }

    function harvestAll() external override whenNotPaused {
        for (uint256 i = 0; i < pools.length; i++) {
            _harvest(i);
        }
    }

    function emergencyHarvest(uint256 poolId) external whenNotPaused {
        PoolInfo memory pool = pools[poolId];
        UserInfo memory user = poolUsers[poolId][msg.sender];
        uint256 pendingReward = user.pendingReward;
        pool.swapAmount = pool.swapAmount.sub(user.swapAmount);
        pool.allocRewardAmount = pool.allocRewardAmount.sub(user.pendingReward);
        user.accRewardAmount = user.accRewardAmount.add(user.pendingReward);
        user.swapAmount = 0;
        user.rewardDebt = 0;
        user.pendingReward = 0;
        _safeRewardTokenTransfer(msg.sender, pendingReward);
        pools[poolId] = pool;
        poolUsers[poolId][msg.sender] = user;
        emit EmergencyWithdraw(msg.sender, poolId, user.swapAmount);
    }

    function getPairs() public view returns (address[] memory) {
        address[] memory pairs = new address[](_swapPairs.length());
        for (uint256 i; i < pairs.length; i++) {
            pairs[i] = _swapPairs.at(i);
        }
        return pairs;
    }

    function getAllPools() external view override returns (PoolInfo[] memory) {
        return pools;
    }

    function getPoolView(uint256 poolId)
        public
        view
        override
        returns (PoolView memory)
    {
        require(poolId < pools.length, "TradingPool: poolId out of range");
        PoolInfo memory pool = pools[poolId];
        IWeleySwapPair pair = IWeleySwapPair(pool.pair);
        IWeleyBEP20 token0 = IWeleyBEP20(pair.token0());
        IWeleyBEP20 token1 = IWeleyBEP20(pair.token1());
        return
            PoolView({
                poolId: poolId,
                pair: pool.pair,
                allocPoint: pool.allocPoint,
                lastRewardBlock: pool.lastRewardBlock,
                accRewardPerShare: pool.accRewardPerShare,
                rewardsPerBlock: pool.allocPoint.mul(rewardTokenPerBlock).div(
                    totalAllocPoint
                ),
                allocRewardAmount: pool.allocRewardAmount,
                accRewardAmount: pool.accRewardAmount,
                swapAmount: pool.swapAmount,
                accSwapAmount: pool.accSwapAmount,
                token0: address(token0),
                symbol0: token0.symbol(),
                name0: token0.name(),
                token1: address(token1),
                symbol1: token1.symbol(),
                name1: token1.name(),
                apr: _getAPR(pool)
            });
    }

    function _getAPR(PoolInfo memory pool) internal view returns (uint256) {
        uint256 tvl = pool.swapAmount;
        uint256 rewardTokenPrice = IWeleySwapOracle(weleySwapOracle)
            .consultInstantPrice(address(rewardToken));

        if (rewardTokenPrice > 0 && tvl > 0) {
            uint256 blockSpeed = IWeleySwapOracle(weleySwapOracle)
                .getBlockSpeed();
            uint256 poolRewardsPerBlock = rewardTokenPerBlock.multiplyDecimal(
                pool.allocPoint.divideDecimal(totalAllocPoint)
            );
            uint256 yearlyRewards = (ONE_YEAR * 1000)
                .div(blockSpeed)
                .mul(poolRewardsPerBlock)
                .multiplyDecimal(uint256(rewardTokenPrice));
            return yearlyRewards.divideDecimal(uint256(tvl)).mul(100);
        }
        return 0;
    }

    function getPoolViewByAddress(address pair)
        public
        view
        override
        returns (PoolView memory)
    {
        return getPoolView(pairPoolIdMap[pair]);
    }

    function getAllPoolViews()
        external
        view
        override
        returns (PoolView[] memory views)
    {
        views = new PoolView[](pools.length);
        for (uint256 i = 0; i < pools.length; i++) {
            views[i] = getPoolView(i);
        }
    }

    function getUserView(address pair, address account)
        public
        view
        override
        returns (UserView memory)
    {
        uint256 poolId = pairPoolIdMap[pair];
        UserInfo memory user = poolUsers[poolId][account];
        return
            UserView({
                swapAmount: user.swapAmount,
                accSwapAmount: user.accSwapAmount,
                unclaimedRewards: pendingRewards(poolId, account),
                accRewardAmount: user.accRewardAmount
            });
    }

    function getUserViews(address account)
        external
        view
        override
        returns (UserView[] memory views)
    {
        views = new UserView[](pools.length);
        for (uint256 i = 0; i < pools.length; i++) {
            views[i] = getUserView(pools[i].pair, account);
        }
    }

    function _phase(uint256 blockNumber) private view returns (uint256) {
        if (halvingPeriod > 0 && blockNumber > startBlock) {
            return (blockNumber.sub(startBlock)).div(halvingPeriod);
        }
        return 0;
    }

    function _getRewardTokenPerBlock(uint256 blockNumber)
        private
        view
        returns (uint256)
    {
        return rewardTokenPerBlock.div(2**_phase(blockNumber));
    }

    function _getRewardTokenBlockReward(uint256 lastRewardBlock)
        public
        view
        returns (uint256)
    {
        uint256 blockReward = 0;
        uint256 lastRewardPhase = _phase(lastRewardBlock);
        uint256 currentPhase = _phase(block.number);
        while (lastRewardPhase < currentPhase) {
            lastRewardPhase++;
            uint256 height = lastRewardPhase.mul(halvingPeriod).add(startBlock);
            blockReward = blockReward.add(
                (height.sub(lastRewardBlock)).mul(
                    _getRewardTokenPerBlock(height)
                )
            );
            lastRewardBlock = height;
        }
        blockReward = blockReward.add(
            (block.number.sub(lastRewardBlock)).mul(
                _getRewardTokenPerBlock(block.number)
            )
        );
        return blockReward;
    }

    function _updatePool(uint256 poolId) private {
        PoolInfo memory pool = pools[poolId];
        if (block.number > pool.lastRewardBlock) {
            if (pool.swapAmount == 0) {
                pool.lastRewardBlock = block.number;
                pools[poolId] = pool;
            } else {
                uint256 blockReward = _getRewardTokenBlockReward(
                    pool.lastRewardBlock
                );
                console.log("blockReward", blockReward);
                if (blockReward > 0) {
                    uint256 tokenReward = blockReward.mul(pool.allocPoint).div(
                        totalAllocPoint
                    );
                    console.log("pool.allocPoint", pool.allocPoint);
                    console.log("totalAllocPoint", totalAllocPoint);
                    console.log("tokenReward", tokenReward);
                    pool.lastRewardBlock = block.number;
                    pool.accRewardPerShare = pool.accRewardPerShare.add(
                        tokenReward.divideDecimal(pool.swapAmount)
                    );
                    console.log(
                        "pool.accRewardPerShare",
                        pool.accRewardPerShare
                    );
                    pool.allocRewardAmount = pool.allocRewardAmount.add(
                        tokenReward
                    );
                    console.log(
                        "pool.allocRewardAmount",
                        pool.allocRewardAmount
                    );
                    pool.accRewardAmount = pool.accRewardAmount.add(
                        tokenReward
                    );
                    pools[poolId] = pool;
                    rewardToken.mint(address(this), tokenReward);
                }
            }
        }
    }

    function updateAllPools() external whenNotPaused {
        _updateAllPools();
    }

    function _updateAllPools() private {
        for (uint256 poolId = 0; poolId < pools.length; ++poolId) {
            _updatePool(poolId);
        }
    }

    function _safeRewardTokenTransfer(address to, uint256 amount) private {
        uint256 rewardTokenBalance = rewardToken.balanceOf(address(this));
        if (amount > rewardTokenBalance) {
            IWeleyBEP20(rewardToken).transfer(to, rewardTokenBalance);
        } else {
            IWeleyBEP20(rewardToken).transfer(to, amount);
        }
    }

    function _registerPair(address pair, uint256 allocPoint) private {
        require(!_swapPairs.contains(pair), "TradingPool: PIAR_EXISTS");

        IWeleySwapPair weleySwapPair = IWeleySwapPair(pair);
        address token0 = weleySwapPair.token0();
        address token1 = weleySwapPair.token1();
        require(
            token0 != address(0) && token1 != address(0),
            "TradingPool: INVALID_PAIR"
        );

        tokenPairs[token0][token1] = pair;
        tokenPairs[token1][token0] = pair;

        _swapPairs.add(pair);
        totalAllocPoint = totalAllocPoint.add(allocPoint);
        PoolInfo memory info;
        info.pair = pair;
        info.allocPoint = allocPoint;
        info.lastRewardBlock = block.number > startBlock
            ? block.number
            : startBlock;
        pools.push(info);
        pairPoolIdMap[pair] = pools.length - 1;
    }

    function _harvest(uint256 poolId) private {
        PoolInfo memory pool = pools[poolId];
        UserInfo memory user = poolUsers[poolId][tx.origin];

        _updatePool(poolId);
        uint256 pendingAmount = pendingRewards(poolId, tx.origin);

        if (pendingAmount > 0) {
            _safeRewardTokenTransfer(tx.origin, pendingAmount);
            pool.swapAmount = pool.swapAmount.sub(user.swapAmount);
            pool.allocRewardAmount = pool.allocRewardAmount.sub(pendingAmount);
            user.accRewardAmount = user.accRewardAmount.add(pendingAmount);
            user.swapAmount = 0;
            user.rewardDebt = 0;
            user.pendingReward = 0;
            pools[poolId] = pool;
            poolUsers[poolId][tx.origin] = user;
        }
        emit Withdraw(tx.origin, poolId, pendingAmount);
    }
}
