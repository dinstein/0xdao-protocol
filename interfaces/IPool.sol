// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

interface IPool {
    function symbol() external view returns (string memory);

    function name() external view returns (string memory);
}
