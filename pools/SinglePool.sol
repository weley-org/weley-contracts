pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "../tokens/interfaces/IBEP20.sol";
import "../swap/interfaces/IWeleySwapOracle.sol";
import "./interfaces/ISinglePool.sol";
import "../libraries/SafeDecimalMath.sol";

contract SinglePool is
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    ISinglePool
{
    using SafeMath for uint256;
    using SafeDecimalMath for uint256;

    mapping(address => UserInfo) public userInfoMap;

    address public depositToken;
    address public rewardToken;

    uint256 public rewardPerBlock;

    uint256 public totalDeposit;

    uint256 public bonusStartBlock;

    uint256 public bonusEndBlock;

    uint256 public lastRewardBlock;

    uint256 public accRewardsPerShare;

    address public weleySwapOracle;

    function initialize(
        address depositToken_,
        address reWardToken_,
        address weleySwapOracle_,
        uint256 rewardPerBlock_,
        uint256 startBlock_,
        uint256 bonusEndBlock_
    ) public initializer {
        __Ownable_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        weleySwapOracle = weleySwapOracle_;
        depositToken = depositToken_;
        rewardToken = reWardToken_;
        rewardPerBlock = rewardPerBlock_;
        lastRewardBlock = startBlock_;
        bonusStartBlock = startBlock_;
        bonusEndBlock = bonusEndBlock_;
    }

    function stopReward() public onlyOwner {
        bonusEndBlock = block.number;
    }

    function emergencyRewardWithdraw(uint256 amount) external onlyOwner {
        require(
            IBEP20(rewardToken).balanceOf(address(this)) >= amount,
            "SinglePool: INSUFICIENT_BALANCE"
        );
        IBEP20(rewardToken).transfer(address(msg.sender), amount);
    }

    function getBlocks() public view returns (uint256) {
        if (bonusStartBlock <= block.number && block.number <= bonusEndBlock) {
            return block.number.sub(lastRewardBlock);
        }
        return 0;
    }

    function pendingReward(address account)
        external
        view
        override
        returns (uint256)
    {
        UserInfo memory user = userInfoMap[account];
        uint256 share = accRewardsPerShare;
        if (block.number > lastRewardBlock && totalDeposit != 0) {
            uint256 tokenReward = getBlocks().mul(rewardPerBlock);
            share = share.add(tokenReward.divideDecimal(totalDeposit));
        }
        return user.amount.multiplyDecimal(share).sub(user.rewardDebt);
    }

    function deposit(uint256 amount)
        external
        override
        nonReentrant
        whenNotPaused
    {
        require(amount > 0, "SinglePool: INSUFICIENT_AMOUNT");
        require(
            IBEP20(depositToken).balanceOf(msg.sender) >= amount,
            "SinglePool: INSUFICIENT_BALANCE"
        );
        require(
            IBEP20(depositToken).allowance(msg.sender, address(this)) >= amount,
            "SinglePool: INSUFICIENT_ALLOWANCE"
        );
        IBEP20(depositToken).transferFrom(msg.sender, address(this), amount);

        UserInfo memory user = userInfoMap[msg.sender];
        _updatePool();
        _harvest(user, msg.sender);

        user.amount = user.amount.add(amount);
        totalDeposit = totalDeposit.add(amount);
        user.rewardDebt = user.amount.multiplyDecimal(accRewardsPerShare);
        userInfoMap[msg.sender] = user;
        emit Deposit(msg.sender, amount);
    }

    function harvest() external override whenNotPaused nonReentrant {
        _updatePool();
        address trader = msg.sender;
        UserInfo memory user = userInfoMap[trader];
        _harvest(user, trader);
        user.rewardDebt = user.amount.multiplyDecimal(accRewardsPerShare);
        userInfoMap[trader] = user;
    }

    function withdraw(uint256 amount)
        external
        override
        whenNotPaused
        nonReentrant
    {
        UserInfo memory user = userInfoMap[msg.sender];
        require(user.amount >= amount, "SinglePool: EXCESSIVE_WITHDRAW_AMOUNT");

        _updatePool();
        _harvest(user, msg.sender);

        if (amount > 0) {
            user.amount = user.amount.sub(amount);
            totalDeposit = totalDeposit.sub(amount);

            IBEP20(depositToken).transfer(address(msg.sender), amount);
        }

        user.rewardDebt = user.amount.multiplyDecimal(accRewardsPerShare);
        userInfoMap[msg.sender] = user;
        emit Withdraw(msg.sender, amount);
    }

    function emergencyWithdraw() external override whenNotPaused nonReentrant {
        UserInfo memory user = userInfoMap[msg.sender];
        IBEP20(depositToken).transfer(address(msg.sender), user.amount);
        user.amount = 0;
        user.rewardDebt = 0;
        userInfoMap[msg.sender] = user;
        emit EmergencyWithdraw(msg.sender, user.amount);
    }

    function _updatePool() private {
        uint256 blocks = getBlocks();
        if (blocks > 0) {
            if (totalDeposit > 0) {
                uint256 tokenReward = blocks.mul(rewardPerBlock);
                accRewardsPerShare = accRewardsPerShare.add(
                    tokenReward.divideDecimal(totalDeposit)
                );
            }
            lastRewardBlock = block.number;
        }
    }

    function _harvest(UserInfo memory user, address account) private {
        _updateBlockSpeed();
        if (user.amount > 0) {
            uint256 pending = user
                .amount
                .multiplyDecimal(accRewardsPerShare)
                .sub(user.rewardDebt);
            if (pending > 0) {
                require(
                    IBEP20(rewardToken).balanceOf(address(this)) >= pending,
                    "SinglePool: INSUFICIENT_REWARD_BALANCE"
                );
                IBEP20(rewardToken).transfer(address(account), pending);
            }
        }
    }

    function _updateBlockSpeed() private {
        IWeleySwapOracle(weleySwapOracle).updateBlock();
    }
}
