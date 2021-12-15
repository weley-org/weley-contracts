pragma solidity ^0.8.0;

interface IWeleySwapOracle {
    function updatePrice(address token0, address token1) external;

    function consultAverageAmountOut(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external view returns (uint256 amountOut);

    function consultInstantAmountOut(
        address tokenIn,
        address tokenOut,
        uint256 tokenAmountIn
    ) external view returns (uint256 tokenAmountOut);

    function consultInstantPrices(address[] memory tokens)
        external
        view
        returns (uint256[] memory);

    function consultInstantPrice(address token) external view returns (uint256);

    function consultPairInstantPrice(address pairAddress)
        external
        view
        returns (uint256);

    function needUpdateBlock() external view returns (bool);

    function updateBlock() external;

    function getBlockSpeed() external view returns (uint256);
}
