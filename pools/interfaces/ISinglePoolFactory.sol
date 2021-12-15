pragma solidity ^0.8.0;

interface ISinglePoolFactory {
    struct PoolView {
        address pool;
        address depositToken;
        address rewardsToken;
        uint256 lastRewardBlock;
        uint256 rewardsPerBlock;
        uint256 accRewardPerShare;
        uint256 totalAmount;
        uint256 bonusStartBlock;
        uint256 bonusEndBlock;
        string depositSymbol;
        string depositName;
        string rewardsSymbol;
        string rewardsName;
        int256 tvl;
        int256 apr;
    }

    struct UserView {
        uint256 stakedAmount;
        uint256 pendingReward;
        uint256 tokenBalance;
    }

    function getPools() external view returns (address[] memory);

    function getAllPoolViews() external view returns (PoolView[] memory);

    function getPoolViewByAddress(address poolAddress)
        external
        view
        returns (PoolView memory);

    function getPoolViewByIndex(uint256 index)
        external
        view
        returns (PoolView memory);

    function getUserView(address poolAddress, address account)
        external
        view
        returns (UserView memory);

    function getUserViews(address account)
        external
        view
        returns (UserView[] memory);

    function getTotalTVL() external view returns (uint256 totalAmount);
}
