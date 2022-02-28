// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

interface ISolidGauge {
    function deposit(uint256, uint256) external;

    function withdraw(uint256) external;

    function balanceOf(address) external view returns (uint256);

    function getReward(address account, address[] memory tokens) external;

    function claimFees() external returns (uint256 claimed0, uint256 claimed1);
}
