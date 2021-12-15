pragma solidity ^0.8.0;

import "hardhat/console.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "../swap/interfaces/IWeleySwapPair.sol";
import "../swap/libraries/FixedPoint.sol";
import "./interfaces/IWeleySwapOracle.sol";

contract WeleySwapOracle is OwnableUpgradeable, IWeleySwapOracle {
    using FixedPoint for *;
    using EnumerableSet for EnumerableSet.AddressSet;

    uint256 public constant UNIT = 10**18;

    uint256 public constant PERIOD = 4 hours;

    uint256 public height0;
    uint256 public timestamp0;
    uint256 public height1;
    uint256 public timestamp1;

    struct PairInfo {
        address token0;
        address token1;
        uint256 price0CumulativeLast;
        uint256 price1CumulativeLast;
        uint32 blockTimestampLast;
        FixedPoint.uq112x112 price0Average;
        FixedPoint.uq112x112 price1Average;
    }

    mapping(address => PairInfo) pairInfos;

    mapping(address => mapping(address => address)) private tokenPairs;

    address public dominationToken;

    EnumerableSet.AddressSet private _pairs;

    mapping(address => mapping(address => address[])) public routerPairs;

    mapping(address => mapping(address => address[])) public routerPaths;

    EnumerableSet.AddressSet private _registeredPairs;

    EnumerableSet.AddressSet private _stableCoins;

    function initialize() public initializer {
        __Ownable_init();
        height0 = block.number;
        timestamp0 = block.timestamp * 1000;
        height1 = block.number;
        timestamp1 = block.timestamp * 1000;
    }

    function addStableCoins(address[] memory coins) public onlyOwner {
        for (uint256 i; i < coins.length; i++) {
            _stableCoins.add(coins[i]);
        }
    }

    function getAllStableCoins() public view returns (address[] memory coins) {
        coins = new address[](_stableCoins.length());
        for (uint256 i; i < coins.length; i++) {
            coins[i] = _stableCoins.at(i);
        }
    }

    function registerRouterPaths(
        address token0,
        address token1,
        address[] memory paths
    ) public onlyOwner {
        require(paths.length > 1, "WeleySwapOracle: INVALID_PATHS");
        routerPaths[token0][token1] = paths;
        uint256 length = paths.length;
        address[] memory revertedPaths = new address[](length);
        for (uint256 i; i < paths.length; i++) {
            revertedPaths[i] = paths[length - i - 1];
        }
        routerPaths[token1][token0] = revertedPaths;
    }

    function getRouterPaths(address token0, address token1)
        public
        view
        returns (address[] memory paths)
    {
        return routerPaths[token0][token1];
    }

    function setDominationToken(address val) public onlyOwner {
        dominationToken = val;
    }

    function registerPairs(address[] memory pairs) public onlyOwner {
        for (uint256 i; i < pairs.length; i++) {
            _registerPair(pairs[i]);
        }
    }

    function registerPair(address pairAddress) public onlyOwner {
        _registerPair(pairAddress);
    }

    function _registerPair(address pairAddress) private {
        IWeleySwapPair pair = IWeleySwapPair(pairAddress);
        (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast) = pair
            .getReserves();

        require(
            reserve0 != 0 && reserve1 != 0,
            "ExampleOracleSimple: NO_RESERVES"
        );

        PairInfo memory pairInfo = pairInfos[pairAddress];
        (address token0, address token1) = (pair.token0(), pair.token1());
        pairInfo.token0 = token0;
        pairInfo.token1 = token1;
        pairInfo.price0CumulativeLast = pair.price0CumulativeLast();
        pairInfo.price1CumulativeLast = pair.price1CumulativeLast();
        pairInfo.blockTimestampLast = blockTimestampLast;
        pairInfos[pairAddress] = pairInfo;

        tokenPairs[token0][token1] = pairAddress;
        tokenPairs[token1][token0] = pairAddress;

        routerPaths[token0][token1] = [token0, token1];
        routerPaths[token1][token0] = [token1, token0];

        if (!_registeredPairs.contains(pairAddress)) {
            _registeredPairs.add(pairAddress);
        }
    }

    function getPairs() public view returns (address[] memory pairs) {
        pairs = new address[](_registeredPairs.length());
        for (uint256 i; i < pairs.length; i++) {
            pairs[i] = _registeredPairs.at(i);
        }
    }

    function consultAverageAmountOut(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external view override returns (uint256 amountOut) {
        address[] memory paths = routerPaths[tokenIn][tokenOut];
        require(paths.length > 1, "INVALID_PATHS");
        amountOut = amountIn;
        for (uint256 i; i < paths.length - 1 && amountOut > 0; i++) {
            address token0 = paths[i];
            address token1 = paths[i + 1];
            amountOut = _consultAverageAmountOut(token0, token1, amountOut);
        }
    }

    function consultInstantAmountOut(
        address tokenIn,
        address tokenOut,
        uint256 tokenAmountIn
    ) public view override returns (uint256 tokenAmountOut) {
        address[] memory paths = routerPaths[tokenIn][tokenOut];
        console.log("tokenIn", tokenIn);
        console.log("tokenOut", tokenOut);
        require(paths.length > 1, "INVALID_PATHS");
        tokenAmountOut = tokenAmountIn;
        for (uint256 i; i < paths.length - 1 && tokenAmountOut > 0; i++) {
            address token0 = paths[i];
            address token1 = paths[i + 1];
            tokenAmountOut = _consultInstantAmountOut(
                token0,
                token1,
                tokenAmountOut
            );
        }
    }

    function consultInstantPrices(address[] memory tokens)
        public
        view
        override
        returns (uint256[] memory prices)
    {
        prices = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            prices[i] = consultInstantPrice(tokens[i]);
        }
    }

    function consultInstantPrice(address token)
        public
        view
        override
        returns (uint256)
    {
        return
            token == dominationToken
                ? UNIT
                : consultInstantAmountOut(token, dominationToken, UNIT);
    }

    function consultPairInstantPrice(address pairAddress)
        public
        view
        override
        returns (uint256 price)
    {
        IWeleySwapPair pair = IWeleySwapPair(pairAddress);
        (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();
        uint256 totalSupply = pair.totalSupply();
        if (reserve0 > 0 && reserve1 > 0 && totalSupply > 0) {
            uint256 amount0 = (uint256(reserve0) * UNIT) / totalSupply;
            uint256 amount1 = (uint256(reserve1) * UNIT) / totalSupply;
            (address token0, address token1) = (pair.token0(), pair.token1());
            uint256 value0 = _stableCoins.contains(token0)
                ? amount0
                : consultInstantAmountOut(token0, dominationToken, amount0);
            uint256 value1 = _stableCoins.contains(token1)
                ? amount1
                : consultInstantAmountOut(token1, dominationToken, amount1);
            if (value0 > 0 && value1 > 0) {
                price = value0 + value1;
            }
        }
    }

    function updatePrice(address token0, address token1) external override {
        address[] memory paths = routerPaths[token0][token1];
        if (paths.length > 1) {
            for (uint256 i = 0; i < paths.length - 1; i++) {
                _updatePrice(paths[i], paths[i + 1]);
            }
        }
    }

    function _updatePrice(address token0, address token1) private {
        address pair = tokenPairs[token0][token1];
        PairInfo memory pairInfo = pairInfos[pair];
        if (pairInfo.token0 != address(0)) {
            (
                uint256 price0Cumulative,
                uint256 price1Cumulative,
                uint32 blockTimestamp
            ) = currentCumulativePrices(pair);
            uint32 timeElapsed = blockTimestamp - pairInfo.blockTimestampLast;

            console.log("timeElapsed", timeElapsed);
            console.log("PERIOD", PERIOD);
            if (timeElapsed >= PERIOD) {
                pairInfo.price0Average = FixedPoint.uq112x112(
                    uint224(
                        (price0Cumulative - pairInfo.price0CumulativeLast) /
                            timeElapsed
                    )
                );
                pairInfo.price1Average = FixedPoint.uq112x112(
                    uint224(
                        (price1Cumulative - pairInfo.price1CumulativeLast) /
                            timeElapsed
                    )
                );
                pairInfo.price0CumulativeLast = price0Cumulative;
                pairInfo.price1CumulativeLast = price1Cumulative;
                pairInfo.blockTimestampLast = blockTimestamp;
                pairInfos[pair] = pairInfo;
            }
        }
    }

    function _consultAverageAmountOut(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) private view returns (uint256 amountOut) {
        address pair = tokenPairs[tokenIn][tokenOut];
        require(pair != address(0), "SwapOracle: PAIR_NOT_FOUND");

        PairInfo memory pairInfo = pairInfos[pair];
        if (tokenIn == pairInfo.token0) {
            amountOut = pairInfo.price0Average.mul(amountIn).decode144();
        } else {
            amountOut = pairInfo.price1Average.mul(amountIn).decode144();
        }
    }

    function currentBlockTimestamp() internal view returns (uint32) {
        return uint32(block.timestamp % 2**32);
    }

    function currentCumulativePrices(address pair)
        internal
        view
        returns (
            uint256 price0Cumulative,
            uint256 price1Cumulative,
            uint32 blockTimestamp
        )
    {
        blockTimestamp = currentBlockTimestamp();
        price0Cumulative = IWeleySwapPair(pair).price0CumulativeLast();
        price1Cumulative = IWeleySwapPair(pair).price1CumulativeLast();

        (
            uint112 reserve0,
            uint112 reserve1,
            uint32 blockTimestampLast
        ) = IWeleySwapPair(pair).getReserves();
        if (blockTimestampLast != blockTimestamp) {
            uint32 timeElapsed = blockTimestamp - blockTimestampLast;

            price0Cumulative +=
                uint256(FixedPoint.fraction(reserve1, reserve0)._x) *
                timeElapsed;

            price1Cumulative +=
                uint256(FixedPoint.fraction(reserve0, reserve1)._x) *
                timeElapsed;
        }
    }

    function needUpdateBlock() external view override returns (bool) {
        return block.number - height0 > 1000 || block.number - height1 > 1000;
    }

    function updateBlock() external override {
        if (block.number - height0 > 1000) {
            height0 = block.number;
        } else if (block.number - height1 > 1000) {
            height1 = block.number;
        }
    }

    function getBlockSpeed() external view override returns (uint256) {
        (uint256 height, uint256 timestamp) = height0 < height1
            ? (height0, timestamp0)
            : (height1, timestamp1);
        return (1000 * block.timestamp - timestamp) / (block.number - height);
    }

    function _consultInstantAmountOut(
        address tokenIn,
        address tokenOut,
        uint256 tokenAmountIn
    ) public view returns (uint256 tokenAmountOut) {
        address pair = tokenPairs[tokenIn][tokenOut];
        console.log("SOL, pair", pair);
        if (pair != address(0)) {
            (uint112 reserve0, uint112 reserve1, ) = IWeleySwapPair(pair)
                .getReserves();
            console.log("reserve0", reserve0);
            console.log("reserve1", reserve1);
            console.log("tokenAmountIn", tokenAmountIn);
            if (reserve0 > 0 && reserve1 > 0) {
                (uint112 tokenInReserve, uint112 tokenOutReserve) = tokenIn <
                    tokenOut
                    ? (reserve0, reserve1)
                    : (reserve1, reserve0);
                uint256 amountOut = (tokenAmountIn * uint256(tokenOutReserve)) /
                    uint256(tokenInReserve);
                console.log("tokenInReserve", tokenInReserve);
                console.log("tokenOutReserve", tokenOutReserve);
                console.log("amountOut", amountOut);
                tokenAmountOut = amountOut;
            }
        }
    }
}
