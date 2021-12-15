pragma solidity ^0.8.0;

import "hardhat/console.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "../libraries/SafeDecimalMath.sol";
import "../tokens/interfaces/IWeleyBEP20.sol";
import "../nft/interfaces/IWeleyNFT.sol";
import "../swap/interfaces/IWeleySwapPair.sol";
import "../swap/interfaces/IWeleySwapOracle.sol";
import "./interfaces/ILiquidityPool.sol";

contract LiquidityPool is
    ILiquidityPool,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable
{
    using SafeMath for uint256;
    using SafeDecimalMath for uint256;
    using EnumerableSet for EnumerableSet.AddressSet;

    uint256 public constant ONE_YEAR = 31536000;

    EnumerableSet.AddressSet private _pairs;

    PoolInfo[] public _pools;

    mapping(uint256 => mapping(address => UserInfo)) private _userInfoMap;

    mapping(address => uint256) private _lpPoolIdMap;

    uint256[] private _additionalRates;

    IWeleyBEP20 public rewardToken;

    uint256 public rewardTokenPerBlock;

    address public feeWallet;

    uint256 public totalAllocPoint;

    uint256 public startBlock;

    uint256 public halvingPeriod;

    uint256 public override nftSlotFee;

    address public weleySwapOracle;

    function initialize(
        IWeleyBEP20 _rewardToken,
        uint256 _rewardPerBlock,
        uint256 _startBlock,
        address _feeWallet,
        address _weleySwapOracle
    ) public initializer {
        __Ownable_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        rewardToken = _rewardToken;
        rewardTokenPerBlock = _rewardPerBlock;
        startBlock = _startBlock;
        weleySwapOracle = _weleySwapOracle;
        feeWallet = _feeWallet;
        _additionalRates = [0, 300, 400, 500, 600, 800, 1000];
        nftSlotFee = SafeDecimalMath.UNIT;
        halvingPeriod = 3952800;
    }

    function phase(uint256 blockNumber) public view returns (uint256) {
        if (halvingPeriod > 0 && blockNumber > startBlock) {
            return (blockNumber.sub(startBlock)).div(halvingPeriod);
        }
        return 0;
    }

    function getRewardTokenPerBlock(uint256 blockNumber)
        public
        view
        override
        returns (uint256)
    {
        uint256 _phase = phase(blockNumber);
        return rewardTokenPerBlock.div(2**_phase);
    }

    function getRewardTokenBlockReward(uint256 _lastRewardBlock)
        public
        view
        override
        returns (uint256)
    {
        uint256 blockReward = 0;
        uint256 lastRewardPhase = phase(_lastRewardBlock);
        uint256 currentPhase = phase(block.number);
        while (lastRewardPhase < currentPhase) {
            lastRewardPhase++;
            uint256 height = lastRewardPhase.mul(halvingPeriod).add(startBlock);
            blockReward = blockReward.add(
                (height.sub(_lastRewardBlock)).mul(
                    getRewardTokenPerBlock(height)
                )
            );
            _lastRewardBlock = height;
        }
        blockReward = blockReward.add(
            (block.number.sub(_lastRewardBlock)).mul(
                getRewardTokenPerBlock(block.number)
            )
        );
        return blockReward;
    }

    function registerLPs(
        address[] memory lps,
        uint256[] memory allocPoints,
        address[] memory additionalNFTs
    ) public onlyOwner {
        for (uint256 i; i < lps.length; i++) {
            _registerLP(lps[i], allocPoints[i], additionalNFTs[i]);
        }
    }

    function registerLP(
        address _lpToken,
        uint256 _allocPoint,
        address _additionalNFT
    ) public onlyOwner {
        _registerLP(_lpToken, _allocPoint, _additionalNFT);
    }

    function _registerLP(
        address _lpToken,
        uint256 _allocPoint,
        address _additionalNFT
    ) private {
        require(_lpToken != address(0), "LiquidityPool: INVALID_LP");
        require(!_pairs.contains(_lpToken), "LiquidityPool: LP_REGISTERED");

        _pairs.add(_lpToken);

        uint256 lastRewardBlock = block.number.max(startBlock);
        totalAllocPoint = totalAllocPoint.add(_allocPoint);

        _pools.push(
            PoolInfo({
                lpToken: _lpToken,
                additionalNFT: _additionalNFT,
                allocPoint: _allocPoint,
                lastRewardBlock: lastRewardBlock,
                accRewardPerShare: 0,
                accDonateAmount: 0,
                totalAmount: 0,
                allocRewardAmount: 0,
                accRewardAmount: 0
            })
        );
        _lpPoolIdMap[_lpToken] = getPoolLength() - 1;
    }

    function setWeleySwapOracle(address val) public onlyOwner {
        weleySwapOracle = val;
    }

    function setPoolAdditionalNFT(uint256 poolId, address _additionalNFT)
        public
        onlyOwner
    {
        require(
            _pools[poolId].additionalNFT == address(0),
            "LiquidityPool:NFT_ALREADY_SET"
        );
        _pools[poolId].additionalNFT = _additionalNFT;
    }

    function setNFTSlotFee(uint256 val) public onlyOwner {
        nftSlotFee = val;
    }

    function updatePoolAllocPoint(uint256 poolId, uint256 _allocPoint)
        public
        onlyOwner
    {
        totalAllocPoint = totalAllocPoint.sub(_pools[poolId].allocPoint).add(
            _allocPoint
        );
        _pools[poolId].allocPoint = _allocPoint;
    }

    function massUpdatePools() public {
        uint256 length = _pools.length;
        for (uint256 poolId = 0; poolId < length; ++poolId) {
            updatePool(poolId);
        }
    }

    function updatePool(uint256 poolId) private {
        _assertPoolId(poolId);
        PoolInfo memory pool = _pools[poolId];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }

        if (pool.totalAmount == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }

        uint256 blockReward = getRewardTokenBlockReward(pool.lastRewardBlock);
        if (blockReward > 0) {
            uint256 tokenReward = blockReward.mul(pool.allocPoint).div(
                totalAllocPoint
            );
            rewardToken.mint(address(this), tokenReward);
            pool.accRewardPerShare = pool.accRewardPerShare.add(
                tokenReward.divideDecimal(pool.totalAmount)
            );
            pool.allocRewardAmount = pool.allocRewardAmount.add(tokenReward);
            pool.accRewardAmount = pool.accRewardAmount.add(tokenReward);
            pool.lastRewardBlock = block.number;
            _pools[poolId] = pool;
        }
    }

    function donateToAll(uint256 donateAmount) public override nonReentrant {
        IWeleyBEP20(rewardToken).transferFrom(
            msg.sender,
            address(this),
            donateAmount
        );

        for (uint256 poolId; poolId < _pools.length; ++poolId) {
            updatePool(poolId);
            PoolInfo memory pool = _pools[poolId];
            if (pool.allocPoint > 0) {
                _donate(
                    pool,
                    poolId,
                    donateAmount.mul(pool.allocPoint).div(totalAllocPoint)
                );
            }
        }
        emit Donate(msg.sender, 100000, donateAmount, donateAmount);
    }

    function donateToPool(uint256 poolId, uint256 donateAmount)
        external
        override
        nonReentrant
    {
        updatePool(poolId);
        IWeleyBEP20(rewardToken).transferFrom(
            msg.sender,
            address(this),
            donateAmount
        );

        PoolInfo memory pool = _pools[poolId];
        require(pool.allocPoint > 0, "LiquidityPool:POOL_CLOSED");
        _donate(pool, poolId, donateAmount);
        emit Donate(msg.sender, poolId, donateAmount, donateAmount);
    }

    function setUserAdditionalNFT(uint256 poolId, uint256 nftId)
        external
        override
        nonReentrant
    {
        updatePool(poolId);
        address account = msg.sender;
        PoolInfo memory pool = _pools[poolId];
        UserInfo memory user = _userInfoMap[poolId][account];

        require(user.additionalNFTId == 0, "LiquidityPool:NFT_ALREADY_SET");

        uint256 level = IWeleyNFT(pool.additionalNFT).getLevel(nftId);
        require(level > 0, "LiquidityPool: INVALID_LEVEL");

        if (nftSlotFee > 0) {
            IWeleyBEP20(rewardToken).transferFrom(
                account,
                feeWallet,
                nftSlotFee
            );
        }

        IWeleyNFT(pool.additionalNFT).transferFrom(
            account,
            address(this),
            nftId
        );
        IWeleyNFT(pool.additionalNFT).burn(nftId);

        if (user.amount > 0) {
            uint256 pending = user
                .amount
                .multiplyDecimal(pool.accRewardPerShare)
                .sub(user.rewardDebt);
            user.rewardPending = user.rewardPending.add(pending);
        }

        user.additionalNFTId = nftId;
        user.additionalRate = _additionalRates[level];

        user.additionalAmount = user.amount.mul(user.additionalRate).div(10000);
        pool.totalAmount = pool.totalAmount.add(user.additionalAmount);

        user.rewardDebt = user
            .amount
            .add(user.additionalAmount)
            .multiplyDecimal(pool.accRewardPerShare);

        _pools[poolId] = pool;
        _userInfoMap[poolId][account] = user;

        emit AdditionalNFT(account, poolId, nftId);
    }

    function updateBlockSpeed() private {
        IWeleySwapOracle(weleySwapOracle).updateBlock();
    }

    function deposit(uint256 poolId, uint256 amount)
        external
        override
        nonReentrant
        whenNotPaused
    {
        updatePool(poolId);
        updateBlockSpeed();

        require(amount > 0, "LiquidityPool: INSUFICIENT_AMOUNT");

        PoolInfo memory pool = _pools[poolId];

        console.log("lp", pool.lpToken);
        console.log("amount", amount);
        console.log(
            "balance",
            IWeleySwapPair(pool.lpToken).balanceOf(msg.sender)
        );
        console.log("address", address(this));

        require(
            IWeleySwapPair(pool.lpToken).balanceOf(msg.sender) >= amount,
            "LiquidityPool: INSUFICIENT_BALANCE"
        );
        require(
            IWeleySwapPair(pool.lpToken).allowance(msg.sender, address(this)) >=
                amount,
            "LiquidityPool: INSUFICIENT_ALLOWANCE"
        );
        IWeleySwapPair(pool.lpToken).transferFrom(
            msg.sender,
            address(this),
            amount
        );

        UserInfo memory user = _userInfoMap[poolId][msg.sender];
        uint256 pending = user
            .amount
            .add(user.additionalAmount)
            .multiplyDecimal(pool.accRewardPerShare)
            .sub(user.rewardDebt);
        user.rewardPending = user.rewardPending.add(pending);

        user.amount = user.amount.add(amount);
        pool.totalAmount = pool.totalAmount.add(amount);
        if (user.additionalRate > 0) {
            uint256 _add = amount.mul(user.additionalRate).div(10000);
            user.additionalAmount = user.additionalAmount.add(_add);
            pool.totalAmount = pool.totalAmount.add(_add);
        }
        user.rewardDebt = user
            .amount
            .add(user.additionalAmount)
            .multiplyDecimal(pool.accRewardPerShare);
        _pools[poolId] = pool;
        _userInfoMap[poolId][msg.sender] = user;

        emit Deposit(msg.sender, poolId, amount);
    }

    function harvest(uint256 poolId)
        external
        override
        nonReentrant
        whenNotPaused
    {
        _harvest(poolId);
    }

    function _harvest(uint256 poolId) private {
        updatePool(poolId);
        updateBlockSpeed();

        PoolInfo memory pool = _pools[poolId];
        UserInfo memory user = _userInfoMap[poolId][msg.sender];

        uint256 pendingAmount = user
            .amount
            .add(user.additionalAmount)
            .multiplyDecimal(pool.accRewardPerShare)
            .sub(user.rewardDebt)
            .add(user.rewardPending);

        if (pendingAmount > 0) {
            IWeleyBEP20(address(rewardToken)).transfer(
                msg.sender,
                pendingAmount
            );

            pool.allocRewardAmount = pool.allocRewardAmount.sub(pendingAmount);
            user.accRewardAmount = user.accRewardAmount.add(pendingAmount);
            user.rewardPending = 0;
            user.rewardDebt = user
                .amount
                .add(user.additionalAmount)
                .multiplyDecimal(pool.accRewardPerShare);

            _pools[poolId] = pool;
            _userInfoMap[poolId][msg.sender] = user;
            emit Harvest(msg.sender, poolId, pendingAmount);
        }
    }

    function pendingRewards(uint256 poolId, address _user)
        public
        view
        override
        returns (uint256)
    {
        PoolInfo memory pool = _pools[poolId];
        UserInfo memory user = _userInfoMap[poolId][_user];
        uint256 accRewardPerShare = pool.accRewardPerShare;

        uint256 pending = 0;
        uint256 amount = user.amount.add(user.additionalAmount);
        if (amount > 0) {
            if (block.number > pool.lastRewardBlock) {
                uint256 blockReward = getRewardTokenBlockReward(
                    pool.lastRewardBlock
                );
                uint256 tokenReward = blockReward.mul(pool.allocPoint).div(
                    totalAllocPoint
                );
                accRewardPerShare = accRewardPerShare.add(
                    tokenReward.divideDecimal(pool.totalAmount)
                );
                pending = amount.multiplyDecimal(accRewardPerShare).sub(
                    user.rewardDebt
                );
            } else if (block.number == pool.lastRewardBlock) {
                pending = amount.multiplyDecimal(accRewardPerShare).sub(
                    user.rewardDebt
                );
            }
        }
        pending = pending.add(user.rewardPending);
        return pending;
    }

    function withdraw(uint256 poolId, uint256 amount)
        external
        override
        nonReentrant
        whenNotPaused
    {
        updatePool(poolId);
        updateBlockSpeed();
        PoolInfo memory pool = _pools[poolId];
        UserInfo memory user = _userInfoMap[poolId][msg.sender];
        require(
            user.amount >= amount,
            "LiquidityPool: EXCESSIVE_WITHDRAW_AMOUNT"
        );
        _harvest(poolId);
        if (amount > 0) {
            IWeleyBEP20(pool.lpToken).transfer(msg.sender, amount);
            pool.totalAmount = pool.totalAmount.sub(amount);
            pool.totalAmount = pool.totalAmount.sub(user.additionalAmount);

            user.amount = user.amount.sub(amount);
            user.additionalAmount = 0;
            user.additionalRate = 0;
            user.additionalNFTId = 0;
            _pools[poolId] = pool;
        }
        user.rewardDebt = user
            .amount
            .add(user.additionalAmount)
            .multiplyDecimal(pool.accRewardPerShare);
        _userInfoMap[poolId][msg.sender] = user;
        emit Withdraw(msg.sender, poolId, amount);
    }

    function harvestAll() external override nonReentrant whenNotPaused {
        for (uint256 i = 0; i < _pools.length; i++) {
            _harvest(i);
        }
    }

    function emergencyWithdraw(uint256 poolId)
        external
        override
        nonReentrant
        whenNotPaused
    {
        updateBlockSpeed();
        PoolInfo memory pool = _pools[poolId];
        UserInfo memory user = _userInfoMap[poolId][msg.sender];

        IWeleyBEP20(pool.lpToken).transfer(msg.sender, user.amount);
        if (pool.totalAmount >= user.amount) {
            pool.totalAmount = pool.totalAmount.sub(user.amount);
        }

        if (pool.totalAmount >= user.additionalAmount) {
            pool.totalAmount = pool.totalAmount.sub(user.additionalAmount);
        }

        emit EmergencyWithdraw(msg.sender, poolId, user.amount);

        user.amount = 0;
        user.rewardDebt = 0;
        user.additionalAmount = 0;
        user.additionalRate = 0;
        user.additionalNFTId = 0;
        _pools[poolId] = pool;
        _userInfoMap[poolId][msg.sender] = user;
    }

    function setRewardTokenPerBlock(uint256 val) public onlyOwner {
        massUpdatePools();
        rewardTokenPerBlock = val;
    }

    function setHalvingPeriod(uint256 val) public onlyOwner {
        halvingPeriod = val;
    }

    function getPairsLength() public view override returns (uint256) {
        return _pairs.length();
    }

    function getPair(uint256 _index) public view override returns (address) {
        require(
            _index <= getPairsLength() - 1,
            "LiquidityPool: index out of bounds"
        );
        return _pairs.at(_index);
    }

    function getPoolLength() public view override returns (uint256) {
        return _pools.length;
    }

    function getPoolView(uint256 poolId)
        public
        view
        override
        returns (PoolView memory)
    {
        require(poolId < _pools.length, "LiquidityPool: poolId out of range");
        PoolInfo memory pool = _pools[poolId];
        address lpToken = pool.lpToken;
        IWeleyBEP20 token0 = IWeleyBEP20(IWeleySwapPair(lpToken).token0());
        IWeleyBEP20 token1 = IWeleyBEP20(IWeleySwapPair(lpToken).token1());
        string memory symbol0 = IWeleyBEP20(address(token0)).symbol();
        string memory name0 = IWeleyBEP20(address(token0)).name();
        uint8 decimals0 = IWeleyBEP20(address(token0)).decimals();
        string memory symbol1 = IWeleyBEP20(address(token1)).symbol();
        string memory name1 = IWeleyBEP20(address(token1)).name();
        uint8 decimals1 = IWeleyBEP20(address(token1)).decimals();
        uint256 rewardsPerBlock = pool.allocPoint.mul(rewardTokenPerBlock).div(
            totalAllocPoint
        );

        return
            PoolView({
                poolId: poolId,
                lpToken: lpToken,
                additionalNFT: pool.additionalNFT,
                allocPoint: pool.allocPoint,
                lastRewardBlock: pool.lastRewardBlock,
                accRewardPerShare: pool.accRewardPerShare,
                rewardsPerBlock: rewardsPerBlock,
                allocRewardAmount: pool.allocRewardAmount,
                accRewardAmount: pool.accRewardAmount,
                totalAmount: pool.totalAmount,
                token0: address(token0),
                symbol0: symbol0,
                name0: name0,
                decimals0: decimals0,
                token1: address(token1),
                symbol1: symbol1,
                name1: name1,
                decimals1: decimals1,
                tvl: int256(_getTVL(pool)),
                apr: int256(_getAPR(pool))
            });
    }

    function _getTVL(PoolInfo memory pool) internal view returns (uint256) {
        uint256 pairPrice = IWeleySwapOracle(weleySwapOracle)
            .consultPairInstantPrice(pool.lpToken);
        if (pairPrice > 0) {
            return pool.totalAmount.multiplyDecimal(uint256(pairPrice));
        }
        return pairPrice;
    }

    function getTVL(uint256 poolId) public view override returns (uint256) {
        return _getTVL(_pools[poolId]);
    }

    function getTVLs() public view override returns (uint256[] memory tvls) {
        tvls = new uint256[](_pools.length);
        for (uint256 i = 0; i < tvls.length; i++) {
            tvls[i] = getTVL(i);
        }
    }

    function getTotalTVL() public view override returns (uint256 totalTVL) {
        uint256[] memory tvls = getTVLs();
        for (uint256 i = 0; i < tvls.length; i++) {
            totalTVL += tvls[i];
        }
    }

    function _getAPR(PoolInfo memory pool) internal view returns (uint256) {
        uint256 tvl = _getTVL(pool);
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

    function getPoolViewByAddress(address lpToken)
        public
        view
        override
        returns (PoolView memory)
    {
        uint256 poolId = _lpPoolIdMap[lpToken];
        return getPoolView(poolId);
    }

    function getRegisteredLps() public view returns (address[] memory pairs) {
        pairs = new address[](_pools.length);
        for (uint256 i = 0; i < pairs.length; i++) {
            pairs[i] = _pools[i].lpToken;
        }
    }

    function getAllPoolViews()
        external
        view
        override
        returns (PoolView[] memory)
    {
        PoolView[] memory views = new PoolView[](_pools.length);
        for (uint256 i = 0; i < _pools.length; i++) {
            views[i] = getPoolView(i);
        }
        return views;
    }

    function getUserView(address lpToken, address account)
        public
        view
        override
        returns (UserView memory)
    {
        uint256 poolId = _lpPoolIdMap[lpToken];
        UserInfo memory user = _userInfoMap[poolId][account];
        uint256 unclaimedRewards = pendingRewards(poolId, account);
        uint256 lpBalance = IWeleyBEP20(lpToken).balanceOf(account);
        return
            UserView({
                stakedAmount: user.amount,
                unclaimedRewards: unclaimedRewards,
                lpBalance: lpBalance,
                accRewardAmount: user.accRewardAmount,
                additionalNFTId: user.additionalNFTId,
                additionalRate: user.additionalRate
            });
    }

    function getUserViews(address account)
        external
        view
        override
        returns (UserView[] memory)
    {
        address lpToken;
        UserView[] memory views = new UserView[](_pools.length);
        for (uint256 i = 0; i < _pools.length; i++) {
            lpToken = address(_pools[i].lpToken);
            views[i] = getUserView(lpToken, account);
        }
        return views;
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes memory
    ) public pure returns (bytes4) {
        return
            bytes4(
                keccak256("onERC721Received(address,address,uint256,bytes)")
            );
    }

    function _donate(
        PoolInfo memory pool,
        uint256 poolId,
        uint256 realAmount
    ) private {
        pool.accRewardPerShare = pool.accRewardPerShare.add(
            realAmount.divideDecimal(pool.totalAmount)
        );
        pool.allocRewardAmount = pool.allocRewardAmount.add(realAmount);
        pool.accDonateAmount = pool.accDonateAmount.add(realAmount);
        _pools[poolId] = pool;
    }

    function _assertPoolId(uint256 poolId) internal view {
        require(poolId < _pools.length, "LiquidityPool: INVALID_POOL_ID");
    }

    function getLevelRates() external view override returns (uint256[] memory) {
        return _additionalRates;
    }

    function getRewardToken() external view override returns (address) {
        return address(rewardToken);
    }
}
