// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;
import "./interfaces/IOxLens.sol";
import "./interfaces/IMultiRewards.sol";
import "./interfaces/IOxPool.sol";
import "./interfaces/IOxdV1Redeem.sol";

/**
 * @title UserProxyStorageLayout
 * @author 0xDAO
 * @notice The primary storage slot layout for UserProxy implementations
 * @dev All implementations must inherit from this contract
 */
contract UserProxyStorageLayout {
    // Versioning
    uint256 public constant verison = 1;

    // Internal interface helpers
    IOxLens internal oxLens;
    IUserProxy internal userProxy;

    // User positions
    mapping(address => bool) public hasStake;
    mapping(uint256 => address) public stakingAddressByIndex;
    mapping(address => uint256) public indexByStakingAddress;
    uint256 public stakingPoolsLength;

    // Public addresses
    address public ownerAddress;
    address public oxLensAddress;
    address public oxSolidAddress;
    address public oxSolidRewardsPoolAddress;
    address public userProxyInterfaceAddress;
    address public vlOxdAddress;

    // Implementations
    address public userProxyLpInteractionsAddress;
    address public userProxyNftInteractionsAddress;
    address public userProxyVotingInteractionsAddress;
}
