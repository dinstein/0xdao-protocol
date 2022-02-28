// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./IMultiRewards.sol";

interface IOxdV1Rewards is IMultiRewards {
    function stakingCap(address account) external view returns (uint256 cap);
}
