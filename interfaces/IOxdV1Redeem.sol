// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

interface IOxdV1Redeem {
    function oxdV1Burnt(address account) external view returns (uint256);

    function redeem(uint256 amount) external;

    function oxdV1() external view returns (IERC20);
}
