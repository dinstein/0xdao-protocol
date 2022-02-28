// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;
import "./IMultiRewards.sol";

interface IPartnersRewards is IMultiRewards {
    function isPartner(address userProxyAddress) external view returns (bool);
}
