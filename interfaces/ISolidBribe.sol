// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

interface ISolidBribe {
    struct RewardPerTokenCheckpoint {
        uint256 timestamp;
        uint256 rewardPerToken;
    }

    function balanceOf(uint256 tokenId) external returns (uint256 balance);

    function getPriorSupplyIndex(uint256 timestamp)
        external
        view
        returns (uint256);

    function rewardPerTokenNumCheckpoints(address rewardTokenAddress)
        external
        view
        returns (uint256);

    function lastUpdateTime(address rewardTokenAddress)
        external
        view
        returns (uint256);

    function batchRewardPerToken(address token, uint256 maxRuns) external;

    function getReward(uint256 tokenId, address[] memory tokens) external;

    function supplyNumCheckpoints() external returns (uint256);

    function rewardPerTokenCheckpoints(address token, uint256 checkpoint)
        external
        view
        returns (RewardPerTokenCheckpoint memory);
}
