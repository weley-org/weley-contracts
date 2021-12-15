pragma solidity ^0.8.0;
import "./IWeleyERC721.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721ReceiverUpgradeable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

interface INFTPool is IERC721ReceiverUpgradeable {
    struct UserInfo {
        uint256 share;
        uint256 rewardDebt;
        EnumerableSet.UintSet nfts;
        uint256 slots;
        mapping(uint256 => uint256[]) slotNFTs;
        uint256 accRewardAmount;
    }

    struct SlotView {
        uint256 index;
        uint256[] tokenIds;
    }

    struct PoolView {
        address weleyToken;
        address rewardToken;
        uint256 lastRewardBlock;
        uint256 rewardsPerBlock;
        uint256 accRewardPerShare;
        uint256 allocRewardAmount;
        uint256 accRewardAmount;
        address gemWeleyNFT;
        string gemWeleyNFTSymbol;
        uint256 gemWeleyNFTAmount;
        uint256 accShare;
    }

    event Stake(address indexed user, uint256 tokenId);
    event StakeWithSlot(address indexed user, uint256 slot, uint256[] tokenIds);
    event Withdraw(address indexed user, uint256 tokenId);
    event EmergencyWithdraw(address indexed user, uint256 tokenId);
    event WithdrawSlot(address indexed user, uint256 slot);
    event EmergencyWithdrawSlot(address indexed user, uint256 slot);

    function rewardTokenPerBlock() external view returns (uint256);

    function enableSlot() external;

    function harvest() external;

    function withdraw(uint256 tokenId) external;

    function withdrawAll() external;

    function emergencyWithdraw(uint256 _tokenId) external;

    function withdrawSlot(uint256 slot) external;

    function emergencyWithdrawSlot(uint256 slot) external;

    function stake(uint256 tokenId) external;

    function batchStake(uint256[] memory tokenIds) external;

    function slotStake(uint256 slot, uint256[] memory tokenIds) external;

    function slotReplace(uint256 slot, uint256[] memory newTokenIds) external;

    function pendingReward(address owner) external view returns (uint256);

    function enableSlotFee() external view returns (uint256);

    function getPoolInfo()
        external
        view
        returns (
            uint256 accShare_,
            uint256 accRewardTokenPerShare_,
            uint256 rewardTokenPerBlock_
        );

    function getPoolView() external view returns (PoolView memory);

    function getUserInfo(address _user)
        external
        view
        returns (
            uint256 share,
            uint256 numNFTs,
            uint256 slotNum,
            uint256 rewardDebt
        );

    function getFullUserInfo(address _user)
        external
        view
        returns (
            uint256 share,
            uint256[] memory nfts,
            uint256 slotNum,
            SlotView[] memory slots,
            uint256 accRewardAmount_,
            uint256 rewardDebt
        );

    function getNFTs(address _user)
        external
        view
        returns (uint256[] memory ids);

    function getSlotNFTsWithIndex(address _user, uint256 i)
        external
        view
        returns (uint256[] memory);

    function getSlotNFTs(address _user)
        external
        view
        returns (SlotView[] memory slots);
}
