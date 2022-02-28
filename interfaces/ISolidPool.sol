// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

interface ISolidPool {
    function token0() external view returns (address);

    function token1() external view returns (address);

    function fees() external view returns (address);

    function stable() external view returns (bool);

    function symbol() external view returns (string memory);

    function approve(address, uint256) external;

    function transfer(address, uint256) external;

    function balanceOf(address) external view returns (uint256);
}
