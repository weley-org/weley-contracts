pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "../tokens/interfaces/IWeleyToken.sol";
import "../swap/libraries/WeleySwapLibrary.sol";
import "../swap/interfaces/IWeleySwapFactory.sol";
import "../swap/interfaces/IWeleySwapPair.sol";
import "../abstracts/Caller.sol";

interface IVWeley {
    function donate(uint256 weleyAmount) external;
}

contract VWeleyTreasury is
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    Caller
{
    event Swap(
        address token0,
        address token1,
        uint256 amountIn,
        uint256 amountOut
    );

    using EnumerableSet for EnumerableSet.AddressSet;
    EnumerableSet.AddressSet private _callers;

    address public weleySwapFactory;
    address public vWeley;
    address public weley;

    function initialize(
        address _weleySwapFactory,
        address _weley,
        address _vWeley
    ) public initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
        __Pausable_init();

        weleySwapFactory = _weleySwapFactory;
        weley = _weley;
        vWeley = _vWeley;

        IWeleyToken(weley).approve(vWeley, type(uint256).max);
    }

    function sendToVWeley() external onlyCaller {
        uint256 balance = IWeleyToken(weley).balanceOf(address(this));
        if (balance > 0) {
            IVWeley(vWeley).donate(balance);
        }
    }

    function batchAnySwapAll(
        address[] memory tokenIns,
        address[] memory tokenOuts
    ) public onlyCaller {
        require(tokenIns.length == tokenOuts.length, "lengths not match");
        for (uint256 i = 0; i < tokenIns.length; i++) {
            anySwapAll(tokenIns[i], tokenOuts[i]);
        }
    }

    function anySwapAll(address _tokenIn, address _tokenOut) public onlyCaller {
        uint256 _amountIn = IERC20(_tokenIn).balanceOf(address(this));
        if (_amountIn > 0) {
            _swap(_tokenIn, _tokenOut, _amountIn, address(this));
        }
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

    function emergencyWithdraw(address _token) public onlyOwner {
        require(
            IERC20(_token).balanceOf(address(this)) > 0,
            "VWeleyTreasury: insufficient contract balance"
        );
        IERC20(_token).transfer(
            msg.sender,
            IERC20(_token).balanceOf(address(this))
        );
    }
}
