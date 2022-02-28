// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;
import "./ISolidlyLens.sol";

interface IOxPool {
    function stakingAddress() external view returns (address);

    function solidPoolAddress() external view returns (address);

    function solidPoolInfo() external view returns (ISolidlyLens.Pool memory);

    function depositLpAndStake(uint256) external;

    function depositLp(uint256) external;

    function withdrawLp(uint256) external;

    function syncBribeTokens() external;

    function notifyBribeOrFees() external;

    function initialize(
        address,
        address,
        address,
        string memory,
        string memory,
        address,
        address
    ) external;

    function gaugeAddress() external view returns (address);
}
