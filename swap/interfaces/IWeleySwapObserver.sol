pragma solidity ^0.8.0;

interface IWeleySwapObserver {
    function onSwap(
        address trader,
        address tokenIn,
        address tokenOut,
        uint256 tokenAmountOut
    ) external;
}
