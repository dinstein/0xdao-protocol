// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IOxSolid is IERC20 {
    function mint(address, uint256) external;

    function convertNftToOxSolid(uint256) external;
}
