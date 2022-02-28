// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./IOxLens.sol";

interface ICvlOxd is IERC20 {
    function minterAddress() external view returns (address);

    function oxLens() external view returns (IOxLens);

    function whitelist(address) external view returns (bool);

    function setMinter(address _minterAddress) external;

    function mint(address to, uint256 amount) external;

    function redeem() external;

    function redeem(uint256 amount) external;

    function redeem(address to, uint256 amount) external;
}
