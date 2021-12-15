pragma solidity ^0.8.0;

import "./IERC20.sol";

interface IBEP20 is IERC20 {
    function decimals() external view returns (uint8);

    function symbol() external view returns (string memory);

    function name() external view returns (string memory);

    function getOwner() external view returns (address);
}
