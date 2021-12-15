pragma solidity ^0.8.4;

import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "../libraries/SafeDecimalMath.sol";
import "./interfaces/IWeleyToken.sol";
import "./interfaces/IVWeley.sol";

contract VWeley is
    OwnableUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    IVWeley
{
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeDecimalMath for uint256;
    using SafeMath for uint256;

    struct StakingInfo {
        uint256 stakingPower;
        uint256 superiorSP;
        address superior;
        uint256 credit;
        uint256 creditDebt;
        uint256 mintedWeley;
        uint256 referralSP;
    }

    uint256 private constant ONE_PERCENT = 10**16;
    uint256 private constant UNIT = 10**18;

    string public override name;
    string public override symbol;
    uint8 public constant override decimals = 18;

    uint256 public minPenaltyRatio;
    uint256 public maxPenaltyRatio;

    uint256 public minMintRatio;
    uint256 public maxMintRatio;

    mapping(address => mapping(address => uint256)) private _allowed;

    address public weleyToken;
    address public weleyTeam;
    address public weleyReserve;
    uint256 public weleyPerBlock;

    uint256 public superiorRatio;
    uint256 public weleyRatio;
    uint256 public weleyFeeBurnRatio;
    uint256 public weleyFeeReserveRatio;

    uint256 public alpha;

    uint256 public totalBlockDistribution;
    uint256 public lastRewardBlock;

    uint256 public totalBlockReward;
    uint256 public totalStakingPower;

    mapping(address => StakingInfo) public stakingInfoMap;

    uint256 public superiorMinWeley;

    mapping(address => EnumerableSet.AddressSet) private _referrals;

    EnumerableSet.AddressSet private _members;

    uint256 public totalReward;

    uint256 public rewardTime0;
    uint256 public totalReward0;

    uint256 public rewardTime1;

    uint256 public totalReward1;

    function updateRewardData() private {
        if (block.timestamp.sub(rewardTime0) > 3600) {
            rewardTime0 = block.timestamp;
            totalReward0 = totalReward;
        }
    }

    function getRewardData()
        public
        view
        returns (
            uint256 minTime,
            uint256 minReward,
            uint256 maxTime,
            uint256 maxReward
        )
    {
        return (rewardTime0, totalReward0, block.timestamp, totalReward);
    }

    function getUserInfo(address user)
        public
        view
        returns (StakingInfo memory)
    {
        return stakingInfoMap[user];
    }

    function initialize(
        string memory name_,
        string memory symbol_,
        address weleyToken_,
        address weleyTeam_,
        address weleyReserve_
    ) public initializer {
        __Ownable_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        weleyToken = weleyToken_;
        weleyTeam = weleyTeam_;
        weleyReserve = weleyReserve_;
        name = name_;
        symbol = symbol_;

        minPenaltyRatio = ONE_PERCENT * 15;
        maxPenaltyRatio = ONE_PERCENT * 80;

        minMintRatio = ONE_PERCENT * 10;
        maxMintRatio = ONE_PERCENT * 80;

        superiorRatio = ONE_PERCENT * 10;
        weleyRatio = 100;

        weleyFeeBurnRatio = ONE_PERCENT * 30;
        weleyFeeReserveRatio = ONE_PERCENT * 20;

        alpha = UNIT;
        superiorMinWeley = 1000 * UNIT;

        setWeleyPerBlock(15 * UNIT);
    }

    function setWeleyPerBlock(uint256 val) public onlyOwner {
        _updateAlpha();
        weleyPerBlock = val;
    }

    function setWeleyFeeBurnRatio(uint256 val) public onlyOwner {
        weleyFeeBurnRatio = val;
    }

    function setWeleyFeeReserveRatio(uint256 val) public onlyOwner {
        weleyFeeReserveRatio = val;
    }

    function setTeamAddress(address val) public onlyOwner {
        weleyTeam = val;
    }

    function setWeleyReserve(address val) public onlyOwner {
        weleyReserve = val;
    }

    function setSuperiorMinWeley(uint256 val) public onlyOwner {
        superiorMinWeley = val;
    }

    function emergencyWithdraw() public onlyOwner {
        uint256 weleyBalance = IWeleyToken(weleyToken).balanceOf(address(this));
        IWeleyToken(weleyToken).transfer(owner(), weleyBalance);
    }

    function doMint(uint256 weleyAmount, address superior)
        public
        override
        whenNotPaused
        nonReentrant
    {
        address account = msg.sender;
        require(superior != account, "VWeley: INVALID_SUPERIOR");
        require(weleyAmount >= UNIT, "VWeley: INSUFICIENT_WELEY_AMOUNT");
        superior = _checkSuperior(account, superior);
        _updateAlpha();
        IWeleyToken(weleyToken).transferFrom(
            account,
            address(this),
            weleyAmount
        );
        _mint(account, weleyAmount);
        _referrals[superior].add(account);
        emit Mint(weleyAmount, superior);
    }

    function getReferrals(address superior)
        external
        view
        override
        returns (address[] memory referrals)
    {
        referrals = new address[](_referrals[superior].length());
        for (uint256 i; i < referrals.length; i++) {
            referrals[i] = _referrals[superior].at(i);
        }
    }

    function doRedeem(uint256 vWeleyAmount, bool all)
        public
        override
        whenNotPaused
        nonReentrant
    {
        require(
            balanceOf(msg.sender) >= vWeleyAmount,
            "VWeley: INSUFICIENT_BALANCE"
        );
        _updateAlpha();
        StakingInfo memory userInfo = stakingInfoMap[msg.sender];
        uint256 weleyAmount;
        if (all) {
            uint256 stakingPower = userInfo.stakingPower.sub(
                userInfo.credit.divideDecimal(alpha)
            );
            weleyAmount = stakingPower.multiplyDecimal(alpha);
        } else {
            weleyAmount = vWeleyAmount.mul(weleyRatio);
        }

        _redeem(msg.sender, weleyAmount);

        uint256 withdrawFeeAmount = weleyAmount.multiplyDecimal(
            getWeleyWithdrawFeeRatio()
        );
        uint256 weleyReceive = weleyAmount.sub(withdrawFeeAmount);
        uint256 burnWeleyAmount = withdrawFeeAmount.multiplyDecimal(
            weleyFeeBurnRatio
        );
        uint256 reserveAmount = withdrawFeeAmount.multiplyDecimal(
            weleyFeeReserveRatio
        );
        withdrawFeeAmount = withdrawFeeAmount.sub(burnWeleyAmount).sub(
            reserveAmount
        );

        IWeleyToken(weleyToken).transfer(msg.sender, weleyReceive);

        if (burnWeleyAmount > 0) {
            IWeleyToken(weleyToken).burn(burnWeleyAmount);
        }

        if (reserveAmount > 0) {
            IWeleyToken(weleyToken).transfer(weleyReserve, reserveAmount);
        }

        if (withdrawFeeAmount > 0) {
            alpha = alpha.add(
                withdrawFeeAmount.divideDecimal(totalStakingPower)
            );
        }

        emit Redeem(
            weleyReceive,
            burnWeleyAmount,
            withdrawFeeAmount,
            reserveAmount
        );
    }

    function donate(uint256 weleyAmount) public override nonReentrant {
        IWeleyToken(weleyToken).transferFrom(
            msg.sender,
            address(this),
            weleyAmount
        );
        alpha = alpha.add(weleyAmount.divideDecimal(totalStakingPower));
        totalReward = totalReward.add(weleyAmount);
        updateRewardData();
    }

    function totalSupply() public view override returns (uint256 vWeleySupply) {
        return
            IWeleyToken(weleyToken)
                .balanceOf(address(this))
                .add(getDistribution())
                .div(weleyRatio);
    }

    function balanceOf(address account)
        public
        view
        override
        returns (uint256 vWeleyAmount)
    {
        vWeleyAmount = weleyBalanceOf(account) / weleyRatio;
    }

    function transfer(address to, uint256 vWeleyAmount)
        public
        override
        whenNotPaused
        nonReentrant
        returns (bool)
    {
        _updateAlpha();
        _transfer(msg.sender, to, vWeleyAmount);
        return true;
    }

    function approve(address spender, uint256 vWeleyAmount)
        public
        override
        whenNotPaused
        nonReentrant
        returns (bool)
    {
        _allowed[msg.sender][spender] = vWeleyAmount;
        emit Approval(msg.sender, spender, vWeleyAmount);
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 vWeleyAmount
    ) public override whenNotPaused nonReentrant returns (bool) {
        require(
            vWeleyAmount <= _allowed[from][msg.sender],
            "ALLOWANCE_NOT_ENOUGH"
        );
        _updateAlpha();
        _transfer(from, to, vWeleyAmount);
        _allowed[from][msg.sender] = _allowed[from][msg.sender].sub(
            vWeleyAmount
        );
        return true;
    }

    function allowance(address owner, address spender)
        public
        view
        override
        returns (uint256)
    {
        return _allowed[owner][spender];
    }

    function getDistribution() public view returns (uint256) {
        return
            lastRewardBlock == 0
                ? 0
                : weleyPerBlock * (block.number - lastRewardBlock);
    }

    function getAlpha() public view returns (uint256) {
        return
            totalStakingPower == 0
                ? alpha
                : alpha.add(getDistribution().divideDecimal(totalStakingPower));
    }

    function weleyBalanceOf(address account) public view returns (uint256) {
        StakingInfo memory userInfo = stakingInfoMap[account];
        (uint256 amount, uint256 credit) = (
            userInfo.stakingPower.multiplyDecimal(getAlpha()),
            userInfo.credit
        );
        return amount > credit ? (amount - credit) : 0;
    }

    function getWeleyWithdrawFeeRatio()
        public
        view
        override
        returns (uint256 feeRatio)
    {
        uint256 input = totalSupply().mul(100).divideCeil(
            getCirculationSupply()
        );
        if (input <= minMintRatio) {
            return maxPenaltyRatio;
        } else if (input >= maxMintRatio) {
            return minPenaltyRatio;
        } else {
            uint256 step = ((maxPenaltyRatio - minPenaltyRatio) * 10) /
                ((maxMintRatio - minMintRatio) / 1e16);
            return maxPenaltyRatio + step - input.multiplyDecimal(step * 10);
        }
    }

    function setRatioValue(uint256 min, uint256 max) public onlyOwner {
        require(max > min, "VWELEY: INVALID_NUM");
        minPenaltyRatio = min;
        maxPenaltyRatio = max;
    }

    function setMintLimitRatio(uint256 min, uint256 max) public onlyOwner {
        require(max < UNIT, "bad max");
        require((max - min) / ONE_PERCENT > 0, "bad max - min");

        minMintRatio = min;
        maxMintRatio = max;
    }

    function getSuperior(address account)
        public
        view
        override
        returns (address superior)
    {
        return stakingInfoMap[account].superior;
    }

    function _updateAlpha() internal {
        alpha = getAlpha();
        lastRewardBlock = block.number;

        uint256 distribution = getDistribution();
        if (distribution > 0) {
            IWeleyToken(weleyToken).mint(address(this), distribution);
            totalBlockReward = totalBlockReward.add(distribution);
            totalReward = totalReward.add(distribution);
            updateRewardData();
        }
    }

    function _mint(address account, uint256 weleyAmount) internal {
        uint256 stakingPower = weleyAmount.divideDecimal(alpha);

        StakingInfo memory userInfo = stakingInfoMap[account];
        StakingInfo memory superiorInfo = stakingInfoMap[userInfo.superior];

        uint256 superiorSP = stakingPower.multiplyDecimal(superiorRatio);

        userInfo.stakingPower = userInfo.stakingPower.add(stakingPower);
        userInfo.superiorSP = userInfo.superiorSP.add(superiorSP);
        userInfo.mintedWeley = userInfo.mintedWeley.add(weleyAmount);

        superiorInfo.stakingPower = superiorInfo.stakingPower.add(superiorSP);
        superiorInfo.credit = superiorInfo.credit.add(
            superiorSP.multiplyDecimal(alpha)
        );
        superiorInfo.referralSP = superiorInfo.referralSP.add(superiorSP);

        totalStakingPower = totalStakingPower.add(stakingPower).add(superiorSP);

        stakingInfoMap[account] = userInfo;
        stakingInfoMap[userInfo.superior] = superiorInfo;

        _members.add(account);
    }

    function getMemberCount() public view returns (uint256) {
        return _members.length();
    }

    function _redeem(address account, uint256 weleyAmount) internal {
        uint256 stakingPower = weleyAmount.divideDecimal(alpha);
        StakingInfo memory userInfo = stakingInfoMap[account];

        userInfo.stakingPower = userInfo.stakingPower.sub(stakingPower);

        uint256 userCreditStakingPower = userInfo.credit.divideDecimal(alpha);

        if (userInfo.stakingPower > userCreditStakingPower) {
            userInfo.stakingPower = userInfo.stakingPower.sub(
                userCreditStakingPower
            );
        } else {
            userCreditStakingPower = userInfo.stakingPower;
            userInfo.stakingPower = 0;
        }

        userInfo.creditDebt = userInfo.creditDebt.add(userInfo.credit);
        userInfo.credit = 0;
        userInfo.mintedWeley = userInfo.mintedWeley > weleyAmount
            ? userInfo.mintedWeley.sub(weleyAmount)
            : 0;

        uint256 superiorDecreasedSP = userInfo.superiorSP.min(
            stakingPower.multiplyDecimal(superiorRatio)
        );
        uint256 superiorDecreasedCredit = superiorDecreasedSP.multiplyDecimal(
            alpha
        );
        userInfo.superiorSP = userInfo.superiorSP.sub(superiorDecreasedSP);

        StakingInfo memory superiorInfo = stakingInfoMap[userInfo.superior];

        if (superiorDecreasedCredit > superiorInfo.creditDebt) {
            uint256 dec = superiorInfo.creditDebt.divideDecimal(alpha);
            superiorDecreasedSP = dec >= superiorDecreasedSP
                ? 0
                : superiorDecreasedSP.sub(dec);
            superiorDecreasedCredit = superiorDecreasedCredit.sub(
                superiorInfo.creditDebt
            );
            superiorInfo.creditDebt = 0;
        } else {
            superiorInfo.creditDebt = superiorInfo.creditDebt.sub(
                superiorDecreasedCredit
            );
            superiorDecreasedCredit = 0;
            superiorDecreasedSP = 0;
        }

        uint256 creditSP = superiorInfo.credit.divideDecimal(alpha);
        if (superiorDecreasedSP >= creditSP) {
            superiorInfo.credit = 0;
            superiorInfo.referralSP = 0;
            superiorInfo.stakingPower = superiorInfo.stakingPower.sub(creditSP);
        } else {
            superiorInfo.credit = superiorInfo.credit.sub(
                superiorDecreasedCredit
            );
            superiorInfo.stakingPower = superiorInfo.stakingPower.sub(
                superiorDecreasedSP
            );
            superiorInfo.referralSP = superiorInfo.referralSP >
                superiorDecreasedSP
                ? superiorInfo.referralSP.sub(superiorDecreasedSP)
                : 0;
        }

        totalStakingPower = totalStakingPower
            .sub(stakingPower)
            .sub(superiorDecreasedSP)
            .sub(userCreditStakingPower);

        stakingInfoMap[account] = userInfo;
        stakingInfoMap[userInfo.superior] = superiorInfo;
    }

    function _transfer(
        address from,
        address to,
        uint256 vWeleyAmount
    ) internal {
        require(balanceOf(from) >= vWeleyAmount, "VWeley: INSUFICIENT_BALANCE");
        require(from != address(0), "VWeley:INVALID_FROM_ADDRESS");
        require(to != address(0), "VWeley:INVALID_TO_ADDRESS");
        require(from != to, "VWeley: FROM==TO");
        uint256 weleyAmount = vWeleyAmount.mul(weleyRatio);
        _redeem(from, weleyAmount);
        _mint(to, weleyAmount);
        emit Transfer(from, to, vWeleyAmount);
    }

    function _checkSuperior(address account, address superior)
        private
        returns (address)
    {
        if (superior == address(0)) {
            superior = weleyTeam;
        }

        StakingInfo memory userInfo = stakingInfoMap[account];

        bool update;

        if (userInfo.superior == address(0)) {
            require(
                superior == weleyTeam ||
                    stakingInfoMap[superior].superior != address(0),
                "VWeley: INVALID_SUPERIOR"
            );
            userInfo.superior = superior;
            update = true;
        }

        if (
            userInfo.superior != weleyTeam &&
            superiorMinWeley > 0 &&
            weleyBalanceOf(userInfo.superior) < superiorMinWeley
        ) {
            userInfo.superior = weleyTeam;
            update = true;
        }

        if (update) {
            stakingInfoMap[account] = userInfo;
        }

        return userInfo.superior;
    }

    function getCirculationSupply()
        public
        view
        override
        returns (uint256 supply)
    {
        supply = IWeleyToken(weleyToken).totalSupply();
    }

    function getOwner() external view override returns (address) {
        return owner();
    }
}
