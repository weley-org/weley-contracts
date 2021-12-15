pragma solidity ^0.8.0;

interface IWeleySwapAggregator {
    event SWAP(
        address indexed sender,
        address[] path,
        uint256 amountIn,
        uint256 amountOut,
        address to
    );

    function getAmountOut(bytes32[] calldata path, uint256 tokenAmountIn)
        external
        view
        returns (uint256 tokenAmountOut);

    function getAmountIn(bytes32[] calldata path, uint256 tokenAmountOut)
        external
        view
        returns (uint256 tokenAmountIn);

    function swapExactTokenForToken(
        bytes32[] calldata symbolPath,
        uint256 tokenAmountIn,
        uint256 tokenAmountOutMin,
        address to,
        uint256 deadline
    ) external payable;

    function swapExactTokenForTokenSupportingFeeOnTransferTokens(
        bytes32[] calldata symbolPath,
        uint256 tokenAmountIn,
        uint256 tokenAmountOutMin,
        address to,
        uint256 deadline
    ) external payable;

    function swapTokenForExactToken(
        bytes32[] calldata symbolPath,
        uint256 tokenAmountInMax,
        uint256 tokenAmountOut,
        address to,
        uint256 deadline
    ) external payable;
}
