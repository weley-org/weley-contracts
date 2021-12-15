pragma solidity ^0.8.0;

interface ILiquidityPool {
    event Deposit(address indexed user, uint256 indexed poolId, uint256 amount);
    event Withdraw(
        address indexed user,
        uint256 indexed poolId,
        uint256 amount
    );
    event Harvest(address indexed user, uint256 indexed poolId, uint256 amount);
    event EmergencyWithdraw(
        address indexed user,
        uint256 indexed poolId,
        uint256 amount
    );
    event Donate(
        address indexed user,
        uint256 poolId,
        uint256 donateAmount,
        uint256 realAmount
    );
    event AdditionalNFT(address indexed user, uint256 poolId, uint256 nftId);

    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
        uint256 rewardPending;
        uint256 accRewardAmount;
        uint256 additionalNFTId;
        uint256 additionalRate;
        uint256 additionalAmount;
    }

    struct UserView {
        uint256 stakedAmount;
        uint256 unclaimedRewards;
        uint256 lpBalance;
        uint256 accRewardAmount;
        uint256 additionalNFTId;
        uint256 additionalRate;
    }

    struct PoolInfo {
        address lpToken;
        address additionalNFT;
        uint256 allocPoint;
        uint256 lastRewardBlock;
        uint256 accRewardPerShare;
        uint256 totalAmount;
        uint256 allocRewardAmount;
        uint256 accRewardAmount;
        uint256 accDonateAmount;
    }

    struct PoolView {
        uint256 poolId;
        address lpToken;
        address additionalNFT;
        uint256 allocPoint;
        uint256 lastRewardBlock;
        uint256 rewardsPerBlock;
        uint256 accRewardPerShare;
        uint256 allocRewardAmount;
        uint256 accRewardAmount;
        uint256 totalAmount;
        address token0;
        string symbol0;
        string name0;
        uint8 decimals0;
        address token1;
        string symbol1;
        string name1;
        uint8 decimals1;
        int256 tvl;
        int256 apr;
    }

    function getRewardTokenPerBlock(uint256 blockNumber)
        external
        view
        returns (uint256);

    function getRewardTokenBlockReward(uint256 _lastRewardBlock)
        external
        view
        returns (uint256);

    function donateToAll(uint256 donateAmount) external;

    function donateToPool(uint256 poolId, uint256 donateAmount) external;

    function setUserAdditionalNFT(uint256 poolId, uint256 nftId) external;

    function deposit(uint256 poolId, uint256 amount) external;

    function harvest(uint256 poolId) external;

    function pendingRewards(uint256 poolId, address _user)
        external
        view
        returns (uint256);

    function withdraw(uint256 poolId, uint256 amount) external;

    function harvestAll() external;

    function emergencyWithdraw(uint256 poolId) external;

    function getPairsLength() external view returns (uint256);

    function getPair(uint256 _index) external view returns (address);

    function getPoolLength() external view returns (uint256);

    function getPoolView(uint256 poolId)
        external
        view
        returns (PoolView memory);

    function getPoolViewByAddress(address lpToken)
        external
        view
        returns (PoolView memory);

    function getAllPoolViews() external view returns (PoolView[] memory);

    function getUserView(address lpToken, address account)
        external
        view
        returns (UserView memory);

    function getUserViews(address account)
        external
        view
        returns (UserView[] memory);

    function getLevelRates() external view returns (uint256[] memory);

    function nftSlotFee() external view returns (uint256);

    function getRewardToken() external view returns (address);

    function getTVL(uint256 poolId) external view returns (uint256);

    function getTVLs() external view returns (uint256[] memory tvls);

    function getTotalTVL() external view returns (uint256 totalTVL);
}
