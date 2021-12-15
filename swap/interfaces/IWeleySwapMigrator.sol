pragma solidity ^0.8.0;

interface IWeleySwapMigrator {
    function desiredLiquidity() external view returns (uint256);
}
