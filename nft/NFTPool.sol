pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721ReceiverUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "../interfaces/IWOKT.sol";
import "../abstracts/Caller.sol";
import "../swap/libraries/TransferHelper.sol";
import "../libraries/SafeDecimalMath.sol";
import "./interfaces/IWeleyNFT.sol";
import "./interfaces/INFTPool.sol";

contract NFTPool is
    INFTPool,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    OwnableUpgradeable,
    Caller
{
    using SafeMath for uint256;
    using SafeDecimalMath for uint256;
    using EnumerableSet for EnumerableSet.UintSet;

    uint256 constant MAX_LEVEL = 6;
    uint256 public constant BONUS_MULTIPLIER = 1;

    address private wort;

    address public weleyToken;
    address public rewardToken;

    address public gemWeleyNFT;

    address public vWeleyTreasury;

    uint256 public override rewardTokenPerBlock;

    mapping(address => UserInfo) private userInfo;

    uint256 public startBlock;
    uint256 public endBlock;

    uint256 lastRewardBlock;
    uint256 accRewardTokenPerShare;

    uint256 public accShare;
    uint256 public allocRewardAmount;
    uint256 public accRewardAmount;

    uint256 public slotAdditionRate;
    uint256 public override enableSlotFee;

    function initialize(
        address _wokt,
        address _weleyToken,
        address _rewardToken,
        address _gemWeleyNFT,
        address _vWeleyTreasury,
        uint256 _startBlock
    ) public initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
        __Pausable_init();

        wort = _wokt;
        weleyToken = _weleyToken;
        gemWeleyNFT = _gemWeleyNFT;
        rewardToken = _rewardToken;
        vWeleyTreasury = _vWeleyTreasury;
        startBlock = _startBlock;
        lastRewardBlock = _startBlock;
        slotAdditionRate = 40000;

        enableSlotFee = 1e14;
    }

    function setEnableSlotFee(uint256 fee) external onlyOwner {
        enableSlotFee = fee;
    }

    function setVWeleyTreasury(address val) external onlyOwner {
        vWeleyTreasury = val;
    }

    function recharge(uint256 amount, uint256 rewardsBlocks)
        external
        onlyCaller
    {
        _updatePool();
        uint256 rewardBalance = IERC20(rewardToken).balanceOf(address(this));
        if (allocRewardAmount > rewardBalance) {
            allocRewardAmount = rewardBalance;
        }
        uint256 remainingBalance = rewardBalance.sub(allocRewardAmount);
        if (remainingBalance > 0 && rewardTokenPerBlock > 0) {
            uint256 remainingBlocks = remainingBalance.div(rewardTokenPerBlock);
            rewardsBlocks = rewardsBlocks.add(remainingBlocks);
        }

        require(
            IERC20(rewardToken).balanceOf(msg.sender) >= amount,
            "NFTPool: INSUFICIENT_BALANCE"
        );
        require(
            IERC20(rewardToken).allowance(msg.sender, address(this)) >= amount,
            "NFTPool: INSUFICIENT_ALLOWANCE"
        );
        IERC20(rewardToken).transferFrom(msg.sender, address(this), amount);

        rewardTokenPerBlock = IERC20(rewardToken)
            .balanceOf(address(this))
            .sub(allocRewardAmount)
            .div(rewardsBlocks);
        endBlock = rewardsBlocks.add(block.number.max(startBlock));
    }

    function enableSlot() external override nonReentrant whenNotPaused {
        require(
            IERC20(weleyToken).balanceOf(msg.sender) >= enableSlotFee,
            "NFTPool: INSUFICIENT_BALANCE"
        );
        require(
            IERC20(weleyToken).allowance(msg.sender, address(this)) >=
                enableSlotFee,
            "NFTPool: INSUFICIENT_ALLOWANCE"
        );
        IERC20(weleyToken).transferFrom(
            msg.sender,
            vWeleyTreasury,
            enableSlotFee
        );
        userInfo[msg.sender].slots += 1;
    }

    function harvest() external override nonReentrant whenNotPaused {
        _harvest();
    }

    function withdraw(uint256 tokenId)
        external
        override
        nonReentrant
        whenNotPaused
    {
        _withdraw(tokenId);
    }

    function withdrawAll() external override nonReentrant whenNotPaused {
        uint256[] memory ids = getNFTs(msg.sender);
        for (uint256 i = 0; i < ids.length; i++) {
            _withdraw(ids[i]);
        }
    }

    function emergencyWithdraw(uint256 _tokenId)
        external
        override
        whenNotPaused
        nonReentrant
    {
        UserInfo storage user = userInfo[msg.sender];
        require(user.nfts.contains(_tokenId), "withdraw: not token onwer");

        user.nfts.remove(_tokenId);

        IWeleyNFT(gemWeleyNFT).transferFrom(
            address(this),
            msg.sender,
            _tokenId
        );
        emit EmergencyWithdraw(msg.sender, _tokenId);

        if (user.share <= accShare) {
            accShare = accShare.sub(user.share);
        } else {
            accShare = 0;
        }
        user.share = 0;
        user.rewardDebt = 0;
    }

    function withdrawSlot(uint256 slot)
        external
        override
        whenNotPaused
        nonReentrant
    {
        _withdrawSlot(slot);
    }

    function emergencyWithdrawSlot(uint256 slot)
        external
        override
        whenNotPaused
        nonReentrant
    {
        UserInfo storage user = userInfo[msg.sender];
        require(slot < user.slots, "slot not enabled");

        uint256[] memory tokenIds = user.slotNFTs[slot];
        delete user.slotNFTs[slot];

        uint256 totalPower;
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            IWeleyNFT.TokenInfo memory info = IWeleyNFT(gemWeleyNFT).getNFT(
                tokenId
            );
            totalPower = totalPower.add(info.power);
            IWeleyNFT(gemWeleyNFT).transferFrom(
                address(this),
                msg.sender,
                tokenId
            );
        }
        totalPower = totalPower.add(
            totalPower.mul(slotAdditionRate).div(10000)
        );

        if (user.share <= accShare) {
            accShare = accShare.sub(user.share);
        } else {
            accShare = 0;
        }
        user.share = 0;
        user.rewardDebt = 0;

        emit EmergencyWithdrawSlot(msg.sender, slot);
    }

    function stake(uint256 tokenId)
        external
        override
        whenNotPaused
        nonReentrant
    {
        _stake(tokenId);
    }

    function batchStake(uint256[] memory tokenIds)
        external
        override
        whenNotPaused
        nonReentrant
    {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            _stake(tokenIds[i]);
        }
    }

    function slotStake(uint256 slot, uint256[] memory tokenIds)
        external
        override
        whenNotPaused
        nonReentrant
    {
        _slotStake(slot, tokenIds);
    }

    function slotReplace(uint256 slot, uint256[] memory newTokenIds)
        external
        override
        whenNotPaused
        nonReentrant
    {
        _withdrawSlot(slot);
        _slotStake(slot, newTokenIds);
    }

    function pendingReward(address owner)
        public
        view
        override
        returns (uint256)
    {
        UserInfo storage user = userInfo[owner];
        uint256 accTokenPerShare = accRewardTokenPerShare;
        uint256 blk = block.number.min(endBlock);
        if (blk > lastRewardBlock && accShare != 0) {
            uint256 tokenReward = blk.sub(lastRewardBlock).mul(
                rewardTokenPerBlock
            );
            accTokenPerShare = accTokenPerShare.add(
                tokenReward.divideDecimal(accShare)
            );
        }
        return
            user.share.multiplyDecimal(accTokenPerShare).sub(user.rewardDebt);
    }

    function getPoolInfo()
        external
        view
        override
        returns (
            uint256 accShare_,
            uint256 accRewardTokenPerShare_,
            uint256 rewardTokenPerBlock_
        )
    {
        return (accShare, accRewardTokenPerShare, rewardTokenPerBlock);
    }

    function getPoolView() public view override returns (PoolView memory) {
        return
            PoolView({
                weleyToken: weleyToken,
                rewardToken: rewardToken,
                lastRewardBlock: lastRewardBlock,
                rewardsPerBlock: rewardTokenPerBlock,
                accRewardPerShare: accRewardTokenPerShare,
                allocRewardAmount: allocRewardAmount,
                accRewardAmount: accRewardAmount,
                gemWeleyNFT: gemWeleyNFT,
                gemWeleyNFTSymbol: IWeleyERC721(gemWeleyNFT).symbol(),
                gemWeleyNFTAmount: IWeleyNFT(gemWeleyNFT).balanceOf(
                    address(this)
                ),
                accShare: accShare
            });
    }

    function getUserInfo(address _user)
        external
        view
        override
        returns (
            uint256 share,
            uint256 numNFTs,
            uint256 slotNum,
            uint256 rewardDebt
        )
    {
        UserInfo storage user = userInfo[_user];
        share = user.share;
        numNFTs = user.nfts.length();
        slotNum = user.slots;
        rewardDebt = user.rewardDebt;
    }

    function getFullUserInfo(address _user)
        external
        view
        override
        returns (
            uint256 share,
            uint256[] memory nfts,
            uint256 slotNum,
            SlotView[] memory slots,
            uint256 userAccRewardAmount,
            uint256 rewardDebt
        )
    {
        UserInfo storage user = userInfo[_user];
        share = user.share;
        nfts = getNFTs(_user);
        slotNum = user.slots;
        slots = getSlotNFTs(_user);
        rewardDebt = user.rewardDebt;
        userAccRewardAmount = user.accRewardAmount;
    }

    function getNFTs(address _user)
        public
        view
        override
        returns (uint256[] memory ids)
    {
        UserInfo storage user = userInfo[_user];
        uint256 len = user.nfts.length();

        uint256[] memory ret = new uint256[](len);
        for (uint256 i = 0; i < len; i++) {
            ret[i] = user.nfts.at(i);
        }
        return ret;
    }

    function getSlotNFTsWithIndex(address _user, uint256 i)
        public
        view
        override
        returns (uint256[] memory)
    {
        return userInfo[_user].slotNFTs[i];
    }

    function getSlotNFTs(address _user)
        public
        view
        override
        returns (SlotView[] memory slots)
    {
        if (userInfo[_user].slots == 0) {
            return slots;
        }
        slots = new SlotView[](userInfo[_user].slots);
        for (uint256 i = 0; i < slots.length; i++) {
            slots[i] = SlotView(i, userInfo[_user].slotNFTs[i]);
        }
    }

    function onERC721Received(
        address operator,
        address,
        uint256,
        bytes calldata
    ) public override nonReentrant returns (bytes4) {
        require(
            operator == address(this),
            "NFTPool: RECEIVED_NFT_FROM_UNAUTHENTICATED_CONTRACCT"
        );
        return
            bytes4(
                keccak256("onERC721Received(address,address,uint256,bytes)")
            );
    }

    receive() external payable {
        assert(msg.sender == wort);
    }

    function _safeTokenTransfer(address to, uint256 amount) private {
        amount = amount.min(IERC20(rewardToken).balanceOf(address(this)));
        if (amount > 0) {
            if (rewardToken == wort) {
                IWOKT(wort).withdraw(amount);
                TransferHelper.safeTransferETH(to, amount);
            } else {
                IERC20(rewardToken).transfer(to, amount);
            }
        }
    }

    function _withdraw(uint256 _tokenId) private {
        UserInfo storage user = userInfo[msg.sender];
        require(user.nfts.contains(_tokenId), "withdraw: not token onwer");

        user.nfts.remove(_tokenId);

        _harvest();

        uint256 power = IWeleyNFT(gemWeleyNFT).getPower(_tokenId);
        accShare = accShare.sub(power);
        user.share = user.share.sub(power);
        user.rewardDebt = user.share.multiplyDecimal(accRewardTokenPerShare);
        IWeleyNFT(gemWeleyNFT).transferFrom(
            address(this),
            msg.sender,
            _tokenId
        );
        emit Withdraw(msg.sender, _tokenId);
    }

    function _stake(uint256 tokenId) private {
        UserInfo storage user = userInfo[msg.sender];
        _updatePool();
        user.nfts.add(tokenId);
        IWeleyNFT(gemWeleyNFT).transferFrom(msg.sender, address(this), tokenId);
        if (user.share > 0) {
            _harvest();
        }

        uint256 power = IWeleyNFT(gemWeleyNFT).getPower(tokenId);
        user.share = user.share.add(power);
        user.rewardDebt = user.share.multiplyDecimal(accRewardTokenPerShare);
        accShare = accShare.add(power);
        emit Stake(msg.sender, tokenId);
    }

    function _slotStake(uint256 slot, uint256[] memory tokenIds) private {
        require(tokenIds.length == MAX_LEVEL, "NFTPool: TOKEN_COUNT_NOT_MATCH");
        UserInfo storage user = userInfo[msg.sender];
        require(slot < user.slots, "NFTPool: SLOT_NOT_ENABLED");
        require(user.slotNFTs[slot].length == 0, "NFTPool: SLOT_ALREADY_USED");

        _updatePool();

        uint256 power;
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            IWeleyNFT.TokenInfo memory info = IWeleyNFT(gemWeleyNFT).getNFT(
                tokenId
            );
            require(info.level == i + 1, "NFTPool: LEVEL_NOT_MATCH");

            power = power.add(info.power);
            IWeleyNFT(gemWeleyNFT).transferFrom(
                msg.sender,
                address(this),
                tokenId
            );
        }
        user.slotNFTs[slot] = tokenIds;

        if (user.share > 0) {
            _harvest();
        }
        power = power.add(power.mul(slotAdditionRate).div(10000));
        user.share = user.share.add(power);
        user.rewardDebt = user.share.multiplyDecimal(accRewardTokenPerShare);
        accShare = accShare.add(power);
        emit StakeWithSlot(msg.sender, slot, tokenIds);
    }

    function _harvest() private {
        _updatePool();
        UserInfo storage user = userInfo[msg.sender];
        uint256 rewardAmount = user
            .share
            .multiplyDecimal(accRewardTokenPerShare)
            .sub(user.rewardDebt);
        _safeTokenTransfer(msg.sender, rewardAmount);

        allocRewardAmount = rewardAmount < allocRewardAmount
            ? allocRewardAmount.sub(rewardAmount)
            : 0;
        user.accRewardAmount = user.accRewardAmount.add(rewardAmount);
        user.rewardDebt = user.share.multiplyDecimal(accRewardTokenPerShare);
    }

    function _updatePool() private {
        uint256 blockNumber = block.number > endBlock ? endBlock : block.number;
        if (block.number >= startBlock && blockNumber > lastRewardBlock) {
            if (accShare > 0) {
                uint256 amount = blockNumber.sub(lastRewardBlock).mul(
                    rewardTokenPerBlock
                );
                accRewardTokenPerShare = accRewardTokenPerShare.add(
                    amount.divideDecimal(accShare)
                );
                allocRewardAmount = allocRewardAmount.add(amount);
                accRewardAmount = accRewardAmount.add(amount);
            }
            lastRewardBlock = blockNumber;
        }
    }

    function _withdrawSlot(uint256 slot) private {
        UserInfo storage user = userInfo[msg.sender];
        require(slot < user.slots, "slot not enabled");

        uint256[] memory tokenIds = user.slotNFTs[slot];
        delete user.slotNFTs[slot];

        _harvest();

        uint256 totalPower;
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            IWeleyNFT.TokenInfo memory info = IWeleyNFT(gemWeleyNFT).getNFT(
                tokenId
            );
            totalPower = totalPower.add(info.power);
            IWeleyNFT(gemWeleyNFT).transferFrom(
                address(this),
                msg.sender,
                tokenId
            );
        }
        totalPower = totalPower.add(
            totalPower.mul(slotAdditionRate).div(10000)
        );

        accShare = accShare.sub(totalPower);
        user.share = user.share.sub(totalPower);
        user.rewardDebt = user.share.multiplyDecimal(accRewardTokenPerShare);
        emit WithdrawSlot(msg.sender, slot);
    }
}
