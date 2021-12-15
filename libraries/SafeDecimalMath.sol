pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";

library SafeDecimalMath {
    using SafeMath for uint256;

    uint8 internal constant decimals = 18;

    uint256 internal constant UNIT = 10**uint256(decimals);

    function unit() internal pure returns (uint256) {
        return UNIT;
    }

    function multiplyDecimal(uint256 x, uint256 y)
        internal
        pure
        returns (uint256)
    {
        return x.mul(y) / UNIT;
    }

    function _multiplyDecimalRound(
        uint256 x,
        uint256 y,
        uint256 precisionUnit
    ) internal pure returns (uint256) {
        uint256 quotientTimesTen = x.mul(y) / (precisionUnit / 10);

        if (quotientTimesTen % 10 >= 5) {
            quotientTimesTen += 10;
        }

        return quotientTimesTen / 10;
    }

    function multiplyDecimalRound(uint256 x, uint256 y)
        internal
        pure
        returns (uint256)
    {
        return _multiplyDecimalRound(x, y, UNIT);
    }

    function divideDecimal(uint256 x, uint256 y)
        internal
        pure
        returns (uint256)
    {
        return x.mul(UNIT).div(y);
    }

    function _divideDecimalRound(
        uint256 x,
        uint256 y,
        uint256 precisionUnit
    ) internal pure returns (uint256) {
        uint256 resultTimesTen = x.mul(precisionUnit * 10).div(y);

        if (resultTimesTen % 10 >= 5) {
            resultTimesTen += 10;
        }

        return resultTimesTen / 10;
    }

    function divideDecimalRound(uint256 x, uint256 y)
        internal
        pure
        returns (uint256)
    {
        return _divideDecimalRound(x, y, UNIT);
    }

    function _divideCeil(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 quotient = a.div(b);
        uint256 remainder = a - quotient * b;
        if (remainder > 0) {
            return quotient + 1;
        } else {
            return quotient;
        }
    }

    function multiplyCeil(uint256 target, uint256 d)
        internal
        pure
        returns (uint256)
    {
        return _divideCeil(target.mul(d), UNIT);
    }

    function divideCeil(uint256 target, uint256 d)
        internal
        pure
        returns (uint256)
    {
        return _divideCeil(target.mul(UNIT), d);
    }

    function min(uint256 x, uint256 y) internal pure returns (uint256) {
        return x < y ? x : y;
    }

    function max(uint256 x, uint256 y) internal pure returns (uint256) {
        return x > y ? x : y;
    }
}
