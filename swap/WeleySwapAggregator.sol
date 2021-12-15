pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./libraries/WeleySwapLibrary.sol";
import "./libraries/WeleySwapMath.sol";
import "./interfaces/IWeleySwapPair.sol";
import "./interfaces/IWOKT.sol";
import "./libraries/TransferHelper.sol";
import "./interfaces/IWeleySwapAggregator.sol";
import "./interfaces/IWeleySwapObserver.sol";

contract WeleySwapAggregator is Ownable, IWeleySwapAggregator {
    uint256 private constant UNIT = 10**uint256(18);
    uint256 private constant MAX_UINT = (2**256) - 1;

    bytes32 private constant BNB = "BNB";
    bytes32 private constant WBNB = "WBNB";

    using WeleySwapMath for uint256;
    using EnumerableSet for EnumerableSet.Bytes32Set;
    using EnumerableSet for EnumerableSet.AddressSet;

    mapping(bytes32 => address) private _tokens;
    EnumerableSet.Bytes32Set private _tokenSymbols;

    mapping(bytes32 => mapping(bytes32 => address)) private _pairs;
    EnumerableSet.AddressSet private _pairAddresses;

    address public weleySwapObserver;

    constructor() Ownable() {}

    modifier ensure(uint256 deadline) {
        require(deadline >= block.timestamp, "WeleySwapAggregator: EXPIRED");
        _;
    }

    receive() external payable {
        require(
            msg.sender == _tokens[WBNB],
            "WeleySwapAggregator: INVALID_MSG_SENDER"
        );
    }

    function setWeleySwapObserver(address value) public onlyOwner {
        weleySwapObserver = value;
    }

    function registerPairs(
        bytes32[] memory tokenASymbols,
        bytes32[] memory tokenBSymbols,
        address[] memory pairAddresses
    ) public onlyOwner {
        require(
            tokenASymbols.length == tokenBSymbols.length,
            "WeleySwapAggregator: INVALID_PARAMETERS"
        );
        require(
            tokenASymbols.length == pairAddresses.length,
            "WeleySwapAggregator: INVALID_PARAMETERS"
        );
        for (uint256 i; i < tokenASymbols.length; i++) {
            (
                bytes32 tokenASymbol,
                bytes32 tokenBSymbol,
                address pairAddress
            ) = (tokenASymbols[i], tokenBSymbols[i], pairAddresses[i]);
            _pairs[tokenASymbol][tokenBSymbol] = pairAddress;
            _pairs[tokenBSymbol][tokenASymbol] = pairAddress;
            _pairAddresses.add(pairAddress);
        }
    }

    function revokePairs(
        bytes32[] calldata tokenASymbols,
        bytes32[] calldata tokenBSymbols
    ) external onlyOwner {
        require(
            tokenASymbols.length == tokenBSymbols.length,
            "WeleySwapAggregator: INVALID_PARAMETERS"
        );
        for (uint256 i; i < tokenASymbols.length; i++) {
            (bytes32 tokenASymbol, bytes32 tokenBSymbol) = (
                tokenASymbols[i],
                tokenBSymbols[i]
            );
            address pairAddress = _pairs[tokenASymbol][tokenBSymbol];
            delete _pairs[tokenASymbol][tokenBSymbol];
            delete _pairs[tokenBSymbol][tokenASymbol];
            _pairAddresses.remove(pairAddress);
        }
    }

    function registerTokens(
        bytes32[] calldata tokenSymbols,
        address[] calldata addresses
    ) external onlyOwner {
        require(
            tokenSymbols.length == addresses.length,
            "WeleySwapAggregator: INVALID_PARAMETERS"
        );
        for (uint256 i; i < tokenSymbols.length; i++) {
            _tokens[tokenSymbols[i]] = addresses[i];
            _tokenSymbols.add(tokenSymbols[i]);
        }
    }

    function revokeTokens(bytes32[] calldata tokenSymbols) external onlyOwner {
        for (uint256 i; i < tokenSymbols.length; i++) {
            delete _tokens[tokenSymbols[i]];
            _tokenSymbols.remove(tokenSymbols[i]);
        }
    }

    function parseSymbolPath(bytes32[] memory symbolPath)
        private
        view
        returns (address[] memory tokenPath, address[] memory pairPath)
    {
        require(symbolPath.length > 1, "WeleySwapAggregator: INVALID_PATH");
        tokenPath = new address[](symbolPath.length);
        pairPath = new address[](symbolPath.length - 1);
        for (uint256 i; i < symbolPath.length; i++) {
            address token = _tokens[symbolPath[i]];
            require(
                token != address(0),
                "WeleySwapAggregator: TOKEN_NOT_REGISTERED"
            );
            tokenPath[i] = token;
            if (i < symbolPath.length - 1) {
                address pair = _pairs[symbolPath[i]][symbolPath[i + 1]];
                require(
                    pair != address(0),
                    "WeleySwapAggregator: PAIR_NOT_REGISTERED"
                );
                pairPath[i] = pair;
            }
        }
    }

    function getAmountOut(bytes32[] calldata path, uint256 tokenAmountIn)
        external
        view
        override
        returns (uint256 tokenAmountOut)
    {
        (
            address[] memory tokenPath,
            address[] memory pairPath
        ) = parseSymbolPath(path);
        return _getAmountOut(tokenPath, pairPath, tokenAmountIn);
    }

    function getAmountIn(bytes32[] calldata path, uint256 tokenAmountOut)
        external
        view
        override
        returns (uint256 tokenAmountIn)
    {
        (
            address[] memory tokenPath,
            address[] memory pairPath
        ) = parseSymbolPath(path);
        return _getAmountIn(tokenPath, pairPath, tokenAmountOut);
    }

    function swapExactTokenForToken(
        bytes32[] calldata symbolPath,
        uint256 tokenAmountIn,
        uint256 tokenAmountOutMin,
        address to,
        uint256 deadline
    ) external payable override ensure(deadline) {
        (
            address[] memory tokenPath,
            address[] memory pairPath
        ) = parseSymbolPath(symbolPath);
        uint256 tokenAmountOut = _getAmountOut(
            tokenPath,
            pairPath,
            tokenAmountIn
        );
        require(
            tokenAmountOut >= tokenAmountOutMin,
            "WeleySwapAggregator: INSUFFICIENT_OUTPUT_AMOUNT"
        );
        _transferTokenIn(symbolPath, tokenPath, pairPath, tokenAmountIn);
        _swap(symbolPath, tokenPath, pairPath, tokenAmountIn, to);
        emit SWAP(msg.sender, tokenPath, tokenAmountIn, tokenAmountOut, to);
    }

    function swapExactTokenForTokenSupportingFeeOnTransferTokens(
        bytes32[] calldata symbolPath,
        uint256 tokenAmountIn,
        uint256 tokenAmountOutMin,
        address to,
        uint256 deadline
    ) external payable override ensure(deadline) {
        (
            address[] memory tokenPath,
            address[] memory pairPath
        ) = parseSymbolPath(symbolPath);
        _transferTokenIn(symbolPath, tokenPath, pairPath, tokenAmountIn);
        uint256 tokenAmountOut = _swapSupportingFeeOnTransferTokens(
            symbolPath,
            tokenPath,
            pairPath,
            to
        );
        require(
            tokenAmountOut >= tokenAmountOutMin,
            "WeleySwapAggregator: INSUFFICIENT_OUTPUT_AMOUNT"
        );
        emit SWAP(msg.sender, tokenPath, tokenAmountIn, tokenAmountOut, to);
    }

    function swapTokenForExactToken(
        bytes32[] calldata symbolPath,
        uint256 tokenAmountInMax,
        uint256 tokenAmountOut,
        address to,
        uint256 deadline
    ) external payable override ensure(deadline) {
        (
            address[] memory tokenPath,
            address[] memory pairPath
        ) = parseSymbolPath(symbolPath);

        uint256 tokenAmountIn = _getAmountIn(
            tokenPath,
            pairPath,
            tokenAmountOut
        );
        require(
            tokenAmountIn <= tokenAmountInMax,
            "WeleySwapAggregator: EXCESSIVE_INPUT_AMOUNT"
        );
        _transferTokenIn(symbolPath, tokenPath, pairPath, tokenAmountIn);
        _swap(symbolPath, tokenPath, pairPath, tokenAmountIn, to);

        emit SWAP(msg.sender, tokenPath, tokenAmountIn, tokenAmountOut, to);
    }

    function _transferTokenIn(
        bytes32[] memory symbolPath,
        address[] memory tokenPath,
        address[] memory pairPath,
        uint256 tokenAmountIn
    ) private {
        if (symbolPath[0] == BNB) {
            require(
                tokenAmountIn <= msg.value,
                "WeleySwapAggregator: INVALID_TOKEN_INPUT_AMOUNT"
            );
            IWOKT(tokenPath[0]).deposit{value: tokenAmountIn}();
            IWOKT(tokenPath[0]).transfer(pairPath[0], tokenAmountIn);
        } else {
            IERC20(tokenPath[0]).transferFrom(
                msg.sender,
                pairPath[0],
                tokenAmountIn
            );
        }
    }

    function _swap(
        bytes32[] memory symbolPath,
        address[] memory tokenPath,
        address[] memory pairPath,
        uint256 tokenAmountIn,
        address to
    ) private {
        uint256 tokenAmountOut;
        bool isBnbOut = symbolPath[symbolPath.length - 1] == BNB;
        for (uint256 i = 0; i < tokenPath.length - 1; i++) {
            tokenAmountOut = _getAmountOut(
                pairPath[i],
                tokenPath[i],
                tokenPath[i + 1],
                tokenAmountIn
            );
            address recipient = i == tokenPath.length - 2
                ? (isBnbOut ? address(this) : to)
                : pairPath[i + 1];
            (uint256 amount0Out, uint256 amount1Out) = tokenPath[i] <
                tokenPath[i + 1]
                ? (uint256(0), tokenAmountOut)
                : (tokenAmountOut, uint256(0));
            IWeleySwapPair(pairPath[i]).swap(
                amount0Out,
                amount1Out,
                recipient,
                new bytes(0)
            );
            if (weleySwapObserver != address(0)) {
                IWeleySwapObserver(weleySwapObserver).onSwap(
                    msg.sender,
                    tokenPath[i],
                    tokenPath[i + 1],
                    tokenAmountOut
                );
            }
            tokenAmountIn = tokenAmountOut;
        }
        if (isBnbOut) {
            IWOKT(tokenPath[tokenPath.length - 1]).withdraw(tokenAmountOut);
            TransferHelper.safeTransferETH(to, tokenAmountOut);
        }

        if (address(this).balance > 0) {
            TransferHelper.safeTransferETH(msg.sender, address(this).balance);
        }
    }

    function _swapSupportingFeeOnTransferTokens(
        bytes32[] memory symbolPath,
        address[] memory tokenPath,
        address[] memory pairPath,
        address to
    ) private returns (uint256) {
        for (uint256 i = 0; i < tokenPath.length - 1; i++) {
            (address tokenIn, address tokenOut, address pair) = (
                tokenPath[i],
                tokenPath[i + 1],
                pairPath[i]
            );
            (uint256 reserve0, uint256 reserve1, ) = IWeleySwapPair(pair)
                .getReserves();
            uint256 amountIn = IERC20(tokenIn).balanceOf(pair).sub(
                tokenIn < tokenOut ? reserve0 : reserve1
            );
            uint256 amountOut = _getAmountOut(
                pair,
                tokenIn,
                tokenOut,
                amountIn
            );
            address recipient = i == tokenPath.length - 2
                ? address(this)
                : pairPath[i + 1];
            (uint256 amount0Out, uint256 amount1Out) = tokenIn < tokenOut
                ? (uint256(0), amountOut)
                : (amountOut, uint256(0));
            IWeleySwapPair(pair).swap(
                amount0Out,
                amount1Out,
                recipient,
                new bytes(0)
            );
            if (weleySwapObserver != address(0)) {
                IWeleySwapObserver(weleySwapObserver).onSwap(
                    msg.sender,
                    tokenIn,
                    tokenOut,
                    amountOut
                );
            }
        }

        {
            address tokenOut = tokenPath[tokenPath.length - 1];
            uint256 tokenAmountOut = IERC20(tokenOut).balanceOf(address(this));
            if (symbolPath[symbolPath.length - 1] == BNB) {
                IWOKT(tokenOut).withdraw(tokenAmountOut);
                TransferHelper.safeTransferETH(to, tokenAmountOut);
            } else {
                TransferHelper.safeTransfer(tokenOut, to, tokenAmountOut);
            }

            if (address(this).balance > 0) {
                TransferHelper.safeTransferETH(
                    msg.sender,
                    address(this).balance
                );
            }
            return tokenAmountOut;
        }
    }

    function queryPairs() public view returns (address[] memory addresses) {
        addresses = new address[](_pairAddresses.length());
        for (uint256 i; i < _pairAddresses.length(); i++) {
            addresses[i] = _pairAddresses.at(i);
        }
    }

    function queryTokens()
        public
        view
        returns (bytes32[] memory symbols, address[] memory addresses)
    {
        symbols = new bytes32[](_tokenSymbols.length());
        addresses = new address[](symbols.length);
        for (uint256 i; i < symbols.length; i++) {
            symbols[i] = _tokenSymbols.at(i);
            addresses[i] = _tokens[symbols[i]];
        }
    }

    function _getReserves(
        address pairAddress,
        address address0,
        address address1
    ) private view returns (uint256 reserve0, uint256 reserve1) {
        (uint112 _reserve0, uint112 _reserve1, ) = IWeleySwapPair(pairAddress)
            .getReserves();
        (reserve0, reserve1) = address0 < address1
            ? (uint256(_reserve0), uint256(_reserve1))
            : (uint256(_reserve1), uint256(_reserve0));
    }

    function _getAmountIn(
        address pairAddress,
        address addressIn,
        address addressOut,
        uint256 amountOut
    ) private view returns (uint256 amountIn) {
        (uint256 reserveIn, uint256 reserveOut) = _getReserves(
            pairAddress,
            addressIn,
            addressOut
        );
        return WeleySwapLibrary.getAmountIn(amountOut, reserveIn, reserveOut);
    }

    function _getAmountIn(
        address[] memory tokenPath,
        address[] memory pairPath,
        uint256 tokenAmountOut
    ) public view returns (uint256 tokenAmountIn) {
        tokenAmountIn = tokenAmountOut;
        for (uint256 i = tokenPath.length - 1; i > 0; i--) {
            tokenAmountIn = _getAmountIn(
                pairPath[i - 1],
                tokenPath[i - 1],
                tokenPath[i],
                tokenAmountIn
            );
        }
    }

    function _getAmountOut(
        address pairAddress,
        address addressIn,
        address addressOut,
        uint256 amountIn
    ) private view returns (uint256 amountOut) {
        (uint256 reserveIn, uint256 reserveOut) = _getReserves(
            pairAddress,
            addressIn,
            addressOut
        );
        return WeleySwapLibrary.getAmountOut(amountIn, reserveIn, reserveOut);
    }

    function _getAmountOut(
        address[] memory tokenPath,
        address[] memory pairPath,
        uint256 tokenAmountIn
    ) private view returns (uint256 tokenAmountOut) {
        tokenAmountOut = tokenAmountIn;
        for (uint256 i; i < tokenPath.length - 1; i++) {
            tokenAmountOut = _getAmountOut(
                pairPath[i],
                tokenPath[i],
                tokenPath[i + 1],
                tokenAmountOut
            );
        }
    }
}
