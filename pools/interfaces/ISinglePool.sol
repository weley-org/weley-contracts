pragma solidity ^0.8.0;

interface ISinglePool {
    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
    }

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 amount);

    function pendingReward(address user) external view returns (uint256);

    function deposit(uint256 amount) external;

    function withdraw(uint256 amount) external;

    function emergencyWithdraw() external;

    function harvest() external;
}
