// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

contract TestCalculation {
    function getPriceUsdc(address tokenAddress)
        external
        view
        returns (uint256)
    {
        return 1000000; // Every token is $1.00
    }
}
