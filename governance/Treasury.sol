pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "../interfaces/IWOKT.sol";
import "../abstracts/Caller.sol";
import "../swap/libraries/WeleySwapLibrary.sol";
import "../swap/interfaces/IWeleySwapFactory.sol";
import "../swap/interfaces/IWeleySwapPair.sol";
import "../tokens/interfaces/IWeleyToken.sol";

interface INFTPool {
    function recharge(uint256 amount, uint256 rewardsBlocks) external;
}

interface ILiquidityPool {
    function donateToAll(uint256 donateAmount) external;

    function donateToPool(uint256 pid, uint256 donateAmount) external;
}

contract Treasury is
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    Caller
{
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeMath for uint256;

    EnumerableSet.AddressSet private _stableCoins;

    address public weleySwapFactory;
    address public USDT;
    address public VAI;
    address public WETH;
    address public WELEY;
    address public team;

    address public nftPool;
    address public liquidityPool;
    address public vWeleyTreasury;
    address public emergencyAddress;

    uint256 constant BASE_RATIO = 1000;

    uint256 public constant lpBonusRatio = 333;

    uint256 public constant nftBonusRatio = 133;

    uint256 public constant weleyLpBonusRatio = 84;

    uint256 public constant vWeleyBonusRatio = 84;

    uint256 public constant teamRatio = 200;

    uint256 public totalFee;

    uint256 public lpBonusAmount;
    uint256 public nftBonusAmount;
    uint256 public weleyLpBonusAmount;
    uint256 public vWeleyBonusAmount;
    uint256 public totalDistributedFee;
    uint256 public totalBurnedWELEY;
    uint256 public totalRepurchasedUSDT;

    struct PairInfo {
        uint256 count;
        uint256 burnedLiquidity;
        address token0;
        address token1;
        uint256 amountOfToken0;
        uint256 amountOfToken1;
    }

    mapping(address => PairInfo) public pairs;

    event Burn(
        address pair,
        uint256 liquidity,
        uint256 amountA,
        uint256 amountB
    );
    event Swap(
        address token0,
        address token1,
        uint256 amountIn,
        uint256 amountOut
    );
    event Distribute(
        uint256 totalAmount,
        uint256 repurchasedAmount,
        uint256 teamAmount,
        uint256 nftBonusAmount,
        uint256 burnedAmount
    );
    event Repurchase(uint256 amountIn, uint256 burnedAmount);
    event NFTPoolTransfer(address nftBonus, uint256 amount);
    event RemoveAndSwapTo(
        address token0,
        address token1,
        address toToken,
        uint256 token0Amount,
        uint256 token1Amount
    );

    function initialize(
        address _weleySwapFactory,
        address _usdt,
        address _vai,
        address _weth,
        address _weley,
        address _vweleyTreasury,
        address _liquidityPool,
        address _nftPool,
        address _teamAddress
    ) public initializer {
        __Ownable_init();
        weleySwapFactory = _weleySwapFactory;
        USDT = _usdt;
        VAI = _vai;
        WETH = _weth;
        WELEY = _weley;
        vWeleyTreasury = _vweleyTreasury;
        liquidityPool = _liquidityPool;
        nftPool = _nftPool;
        team = _teamAddress;
    }

    function setEmergencyAddress(address val) public onlyOwner {
        require(val != address(0), "Treasury: address is zero");
        emergencyAddress = val;
    }

    function setTeamAddress(address val) public onlyOwner {
        require(val != address(0), "Treasury: address is zero");
        team = val;
    }

    function setNFTPool(address val) public onlyOwner {
        require(val != address(0), "Treasury: address is zero");
        nftPool = val;
    }

    function setLpPool(address val) public onlyOwner {
        require(val != address(0), "Treasury: address is zero");
        liquidityPool = val;
    }

    function setVWeleyTreasury(address val) public onlyOwner {
        require(val != address(0), "Treasury: address is zero");
        vWeleyTreasury = val;
    }

    function _removeLiquidity(address _token0, address _token1)
        internal
        returns (uint256 amount0, uint256 amount1)
    {
        address pair = IWeleySwapFactory(weleySwapFactory).getPair(
            _token0,
            _token1
        );
        uint256 liquidity = IERC20(pair).balanceOf(address(this));
        if (liquidity == 0) {
            return (0, 0);
        }

        (uint112 _reserve0, uint112 _reserve1, ) = IWeleySwapPair(pair)
            .getReserves();
        uint256 totalSupply = IWeleySwapPair(pair).totalSupply();
        amount0 = liquidity.mul(_reserve0) / totalSupply;
        amount1 = liquidity.mul(_reserve1) / totalSupply;
        if (amount0 == 0 || amount1 == 0) {
            return (0, 0);
        }

        IWeleySwapPair(pair).transfer(pair, liquidity);
        (amount0, amount1) = IWeleySwapPair(pair).burn(address(this));

        pairs[pair].count += 1;
        pairs[pair].burnedLiquidity = pairs[pair].burnedLiquidity.add(
            liquidity
        );
        if (pairs[pair].token0 == address(0)) {
            pairs[pair].token0 = IWeleySwapPair(pair).token0();
            pairs[pair].token1 = IWeleySwapPair(pair).token1();
        }
        pairs[pair].amountOfToken0 = pairs[pair].amountOfToken0.add(amount0);
        pairs[pair].amountOfToken1 = pairs[pair].amountOfToken1.add(amount1);

        emit Burn(pair, liquidity, amount0, amount1);
    }

    function _swap(
        address _tokenIn,
        address _tokenOut,
        uint256 _amountIn,
        address _to
    ) internal returns (uint256 amountOut) {
        address pair = IWeleySwapFactory(weleySwapFactory).getPair(
            _tokenIn,
            _tokenOut
        );
        (uint256 reserve0, uint256 reserve1, ) = IWeleySwapPair(pair)
            .getReserves();

        (uint256 reserveInput, uint256 reserveOutput) = _tokenIn ==
            IWeleySwapPair(pair).token0()
            ? (reserve0, reserve1)
            : (reserve1, reserve0);
        amountOut = WeleySwapLibrary.getAmountOut(
            _amountIn,
            reserveInput,
            reserveOutput
        );
        IERC20(_tokenIn).transfer(pair, _amountIn);

        _tokenIn == IWeleySwapPair(pair).token0()
            ? IWeleySwapPair(pair).swap(0, amountOut, _to, new bytes(0))
            : IWeleySwapPair(pair).swap(amountOut, 0, _to, new bytes(0));

        emit Swap(_tokenIn, _tokenOut, _amountIn, amountOut);
    }

    function anySwap(
        address _tokenIn,
        address _tokenOut,
        uint256 _amountIn
    ) external onlyCaller {
        _swap(_tokenIn, _tokenOut, _amountIn, address(this));
    }

    function anySwapAll(address _tokenIn, address _tokenOut) public onlyCaller {
        uint256 _amountIn = IERC20(_tokenIn).balanceOf(address(this));
        if (_amountIn == 0) {
            return;
        }
        _swap(_tokenIn, _tokenOut, _amountIn, address(this));
    }

    function batchAnySwapAll(
        address[] memory _tokenIns,
        address[] memory _tokenOuts
    ) public onlyCaller {
        require(_tokenIns.length == _tokenOuts.length, "lengths not match");
        for (uint256 i = 0; i < _tokenIns.length; i++) {
            anySwapAll(_tokenIns[i], _tokenOuts[i]);
        }
    }

    function removeAndSwapTo(
        address _token0,
        address _token1,
        address _toToken
    ) public onlyCaller {
        (address token0, address token1) = WeleySwapLibrary.sortTokens(
            _token0,
            _token1
        );
        (uint256 amount0, uint256 amount1) = _removeLiquidity(token0, token1);

        if (amount0 > 0 && token0 != _toToken) {
            _swap(token0, _toToken, amount0, address(this));
        }
        if (amount1 > 0 && token1 != _toToken) {
            _swap(token1, _toToken, amount1, address(this));
        }

        emit RemoveAndSwapTo(token0, token1, _toToken, amount0, amount1);
    }

    function batchRemoveAndSwapTo(
        address[] memory _token0s,
        address[] memory _token1s,
        address[] memory _toTokens
    ) public onlyCaller {
        require(_token0s.length == _token1s.length, "lengths not match");
        require(_token1s.length == _toTokens.length, "lengths not match");

        for (uint256 i = 0; i < _token0s.length; i++) {
            removeAndSwapTo(_token0s[i], _token1s[i], _toTokens[i]);
        }
    }

    function swap(address _token0, address _token1) public onlyCaller {
        require(
            isStableCoin(_token0) || isStableCoin(_token1),
            "Treasury: must has a stable coin"
        );

        (address token0, address token1) = WeleySwapLibrary.sortTokens(
            _token0,
            _token1
        );
        (uint256 amount0, uint256 amount1) = _removeLiquidity(token0, token1);

        uint256 amountOut;
        if (isStableCoin(token0)) {
            amountOut = _swap(token1, token0, amount1, address(this));
            if (token0 != USDT) {
                amountOut = _swap(
                    token0,
                    USDT,
                    amountOut.add(amount0),
                    address(this)
                );
            }
        } else {
            amountOut = _swap(token0, token1, amount0, address(this));
            if (token1 != USDT) {
                amountOut = _swap(
                    token1,
                    USDT,
                    amountOut.add(amount1),
                    address(this)
                );
            }
        }

        totalFee = totalFee.add(amountOut);
    }

    function getRemaining() public view onlyCaller returns (uint256 remaining) {
        uint256 pending = lpBonusAmount
            .add(nftBonusAmount)
            .add(weleyLpBonusAmount)
            .add(vWeleyBonusAmount);
        uint256 bal = IERC20(USDT).balanceOf(address(this));
        if (bal <= pending) {
            return 0;
        }
        remaining = bal.sub(pending);
    }

    function distribute(uint256 _amount) public onlyCaller {
        uint256 remaining = getRemaining();
        if (_amount == 0) {
            _amount = remaining;
        }
        require(
            _amount <= remaining,
            "Treasury: amount exceeds remaining of contract"
        );

        uint256 curAmount = _amount;

        uint256 _lpBonusAmount = _amount.mul(lpBonusRatio).div(BASE_RATIO);
        curAmount = curAmount.sub(_lpBonusAmount);

        uint256 _nftBonusAmount = _amount.mul(nftBonusRatio).div(BASE_RATIO);
        curAmount = curAmount.sub(_nftBonusAmount);

        uint256 _weleyLpBonusAmount = _amount.mul(weleyLpBonusRatio).div(
            BASE_RATIO
        );
        curAmount = curAmount.sub(_weleyLpBonusAmount);

        uint256 _vWeleyBonusAmount = _amount.mul(vWeleyBonusRatio).div(
            BASE_RATIO
        );
        curAmount = curAmount.sub(_vWeleyBonusAmount);

        uint256 _teamAmount = _amount.mul(teamRatio).div(BASE_RATIO);
        curAmount = curAmount.sub(_teamAmount);

        uint256 _repurchasedAmount = curAmount;
        uint256 _burnedAmount = repurchase(_repurchasedAmount);

        IERC20(USDT).transfer(team, _teamAmount);

        lpBonusAmount = lpBonusAmount.add(_lpBonusAmount);
        nftBonusAmount = nftBonusAmount.add(_nftBonusAmount);
        weleyLpBonusAmount = weleyLpBonusAmount.add(_weleyLpBonusAmount);
        vWeleyBonusAmount = vWeleyBonusAmount.add(_vWeleyBonusAmount);
        totalDistributedFee = totalDistributedFee.add(_amount);

        emit Distribute(
            _amount,
            _repurchasedAmount,
            _teamAmount,
            _nftBonusAmount,
            _burnedAmount
        );
    }

    function sendToLpPool(uint256 _amountUSD) public onlyCaller {
        require(
            _amountUSD <= lpBonusAmount,
            "Treasury: amount exceeds lp bonus amount"
        );
        lpBonusAmount = lpBonusAmount.sub(_amountUSD);

        uint256 _amount = swapUSDToWELEY(_amountUSD);
        IERC20(WELEY).approve(liquidityPool, _amount);
        ILiquidityPool(liquidityPool).donateToAll(_amount);
    }

    function sendToWELEYLpPool(uint256 _amountUSD, uint256 pid)
        public
        onlyCaller
    {
        require(
            _amountUSD <= weleyLpBonusAmount,
            "Treasury: amount exceeds weley lp bonus amount"
        );
        weleyLpBonusAmount = weleyLpBonusAmount.sub(_amountUSD);

        uint256 _amount = swapUSDToWELEY(_amountUSD);
        IERC20(WELEY).approve(liquidityPool, _amount);
        ILiquidityPool(liquidityPool).donateToPool(pid, _amount);
    }

    function sendToNFTPool(uint256 _amountUSD, uint256 _rewardsBlocks)
        public
        onlyCaller
    {
        require(
            _amountUSD <= nftBonusAmount,
            "Treasury: amount exceeds nft bonus amount"
        );
        nftBonusAmount = nftBonusAmount.sub(_amountUSD);

        uint256 _amount = swapUSDToWETH(_amountUSD);

        IWOKT(WETH).approve(nftPool, _amount);
        INFTPool(nftPool).recharge(_amount, _rewardsBlocks);
        emit NFTPoolTransfer(nftPool, _amount);
    }

    function sendToVWELEY(uint256 _amountUSD) public onlyCaller {
        require(
            _amountUSD <= vWeleyBonusAmount,
            "Treasury: amount exceeds vWeley bonus amount"
        );
        vWeleyBonusAmount = vWeleyBonusAmount.sub(_amountUSD);

        uint256 _amount = swapUSDToWELEY(_amountUSD);
        IERC20(WELEY).transfer(vWeleyTreasury, _amount);
    }

    function repurchase(uint256 _amountIn)
        internal
        returns (uint256 amountOut)
    {
        require(
            IERC20(USDT).balanceOf(address(this)) >= _amountIn,
            "Treasury: amount is less than USDT balance"
        );

        amountOut = swapUSDToWELEY(_amountIn);
        IWeleyToken(WELEY).burn(amountOut);

        totalRepurchasedUSDT = totalRepurchasedUSDT.add(_amountIn);
        totalBurnedWELEY = totalBurnedWELEY.add(amountOut);
    }

    function sendAll(uint256 _nftRewardsBlocks, uint256[] memory pids)
        external
        onlyCaller
    {
        if (lpBonusAmount > 0) {
            sendToLpPool(lpBonusAmount);
        }

        if (vWeleyBonusAmount > 0) {
            sendToVWELEY(vWeleyBonusAmount);
        }

        if (_nftRewardsBlocks > 0) {
            sendToNFTPool(nftBonusAmount, _nftRewardsBlocks);
        }

        if (pids.length > 0 && weleyLpBonusAmount > 0) {
            uint256 amount = weleyLpBonusAmount.div(pids.length);
            for (uint256 i = 0; i < pids.length; i++) {
                sendToWELEYLpPool(amount, pids[i]);
            }
        }
    }

    function emergencyWithdraw(address _token) public onlyOwner {
        require(
            IERC20(_token).balanceOf(address(this)) > 0,
            "Treasury: insufficient contract balance"
        );
        IERC20(_token).transfer(
            emergencyAddress,
            IERC20(_token).balanceOf(address(this))
        );
    }

    function swapUSDToWELEY(uint256 _amountUSD)
        internal
        returns (uint256 amountOut)
    {
        uint256 balOld = IERC20(WELEY).balanceOf(address(this));

        _swap(USDT, VAI, _amountUSD, address(this));
        uint256 amountVAI = IERC20(VAI).balanceOf(address(this));
        _swap(VAI, WELEY, amountVAI, address(this));

        amountOut = IERC20(WELEY).balanceOf(address(this)).sub(balOld);
    }

    function swapUSDToWETH(uint256 _amountUSD)
        internal
        returns (uint256 amountOut)
    {
        uint256 balOld = IERC20(WETH).balanceOf(address(this));
        _swap(USDT, WETH, _amountUSD, address(this));
        amountOut = IERC20(WETH).balanceOf(address(this)).sub(balOld);
    }

    function addStableCoin(address _token) public onlyOwner returns (bool) {
        require(_token != address(0), "Treasury: address is zero");
        return _stableCoins.add(_token);
    }

    function delStableCoin(address _token) public onlyOwner returns (bool) {
        require(_token != address(0), "Treasury: address is zero");
        return _stableCoins.remove(_token);
    }

    function getStableCoinLength() public view returns (uint256) {
        return _stableCoins.length();
    }

    function isStableCoin(address _token) public view returns (bool) {
        return _stableCoins.contains(_token);
    }

    function getStableCoin(uint256 _index) public view returns (address) {
        require(
            _index <= getStableCoinLength() - 1,
            "Treasury: index out of bounds"
        );
        return _stableCoins.at(_index);
    }
}
