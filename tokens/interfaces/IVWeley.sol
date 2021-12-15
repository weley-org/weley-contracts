import "./IBEP20.sol";
pragma solidity ^0.8.0;

interface IVWeley is IBEP20 {
    event Mint(uint256 weleyAmount, address superior);

    event Redeem(
        uint256 weleyReceive,
        uint256 burnWeleyAmount,
        uint256 withdrawFeeAmount,
        uint256 reserveAmount
    );

    function getReferrals(address superior)
        external
        view
        returns (address[] memory referrals);

    function getCirculationSupply() external view returns (uint256 supply);

    function getSuperior(address account)
        external
        view
        returns (address superior);

    function getWeleyWithdrawFeeRatio()
        external
        view
        returns (uint256 feeRatio);

    function donate(uint256 weleyAmount) external;

    function doMint(uint256 weleyAmount, address superiorAddress) external;

    function doRedeem(uint256 vWeleyAmount, bool all) external;
}
