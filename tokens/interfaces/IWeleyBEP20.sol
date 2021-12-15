pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";

interface IWeleyBEP20 is IERC20MetadataUpgradeable {
    function getOwner() external view returns (address);

    function mint(address account, uint256 amount) external;

    function burn(uint256 amount) external;
}
