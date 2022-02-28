// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

interface IRewardsDistributor {
    function notifyRewardAmount(
        address stakingAddress,
        address rewardToken,
        uint256 amount
    ) external;
}
