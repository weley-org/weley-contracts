pragma solidity ^0.8.0;

interface ITradingPool {
    struct UserInfo {
        uint256 swapAmount;
        uint256 accSwapAmount;
        uint256 pendingReward;
        uint256 rewardDebt;
        uint256 accRewardAmount;
    }

    struct UserView {
        uint256 swapAmount;
        uint256 accSwapAmount;
        uint256 unclaimedRewards;
        uint256 accRewardAmount;
    }

    struct PoolInfo {
        address pair;
        uint256 allocPoint;
        uint256 lastRewardBlock;
        uint256 accRewardPerShare;
        uint256 swapAmount;
        uint256 accSwapAmount;
        uint256 allocRewardAmount;
        uint256 accRewardAmount;
    }

    struct PoolView {
        uint256 poolId;
        address pair;
        uint256 allocPoint;
        uint256 lastRewardBlock;
        uint256 rewardsPerBlock;
        uint256 accRewardPerShare;
        uint256 allocRewardAmount;
        uint256 accRewardAmount;
        uint256 swapAmount;
        uint256 accSwapAmount;
        address token0;
        string symbol0;
        string name0;
        address token1;
        string symbol1;
        string name1;
        uint256 apr;
    }

    event Swap(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(
        address indexed user,
        uint256 indexed pid,
        uint256 amount
    );

    function pendingRewards(uint256 poolId, address user)
        external
        view
        returns (uint256);

    function harvest(uint256 poolId) external;

    function harvestAll() external;

    function getAllPools() external view returns (PoolInfo[] memory);

    function getPoolView(uint256 poolId)
        external
        view
        returns (PoolView memory);

    function getPoolViewByAddress(address pair)
        external
        view
        returns (PoolView memory);

    function getAllPoolViews() external view returns (PoolView[] memory views);

    function getUserView(address pair, address account)
        external
        view
        returns (UserView memory);

    function getUserViews(address account)
        external
        view
        returns (UserView[] memory);
}
