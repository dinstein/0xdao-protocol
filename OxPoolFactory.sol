// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Wrapper.sol";
import "./interfaces/IPool.sol";
import "./interfaces/IMultiRewards.sol";
import "./interfaces/IOxPool.sol";
import "./interfaces/IOxPoolProxy.sol";
import "./interfaces/ISolidlyLens.sol";
import "./interfaces/IUserProxy.sol";
import "./interfaces/IVoter.sol";
import "./ProxyImplementation.sol";

/**
 * @title OxPoolFactory
 * @author 0xDAO
 * @dev Responsible for creating new oxPools
 * @dev For every Solidly pool there will be a corresponding oxPool
 * @dev A sync mechanism is utilized to automatically generate new oxPools when new Solidly pools are detected
 * @dev The sync mechanism utilizes EIP-1167 for very inexpensive contract deployments
 */
contract OxPoolFactory is ProxyImplementation {
    /*******************************************************
     *                     Configuration
     *******************************************************/

    // Important addresses
    address public multiRewardsTemplateAddress;
    address public oxdAddress;
    address public oxPoolImplementationSourceAddress;
    address public oxPoolProxyTemplateAddress;
    address public oxSolidAddress;
    address public oxSolidStakingPoolAddress;
    address public oxSolidRewardsPoolAddress;
    address public rewardsDistributorAddress;
    address public solidlyLensAddress;
    address public tokensAllowlist;
    address public userProxyTemplateAddress;
    address public voterProxyAddress;
    address public vlOxdAddress;
    address internal oxPoolFactoryAddress;

    // oxPool syncing variables
    uint256 public syncedPoolsLength;
    mapping(address => address) public oxPoolBySolidPool;
    mapping(address => address) public solidPoolByOxPool;
    address[] public oxPools;

    // Interfaces
    ISolidlyLens solidlyLens;
    IVoter voter;

    /**
     * @notice Initialize proxy storage
     */
    function initializeProxyStorage(
        address _solidlyLensAddress,
        address _oxPoolImplementationSourceAddress,
        address _oxPoolProxyTemplateAddress,
        address _multiRewardsTemplateAddress,
        address _voterProxyAddress,
        address _rewardsDistributorAddress,
        address _oxdAddress,
        address _vlOxdAddress,
        address _oxSolidAddress,
        address _oxSolidRewardsPoolAddress,
        address _tokensAllowlist
    ) public checkProxyInitialized {
        multiRewardsTemplateAddress = _multiRewardsTemplateAddress;
        rewardsDistributorAddress = _rewardsDistributorAddress;
        oxdAddress = _oxdAddress;
        oxPoolImplementationSourceAddress = _oxPoolImplementationSourceAddress;
        oxPoolProxyTemplateAddress = _oxPoolProxyTemplateAddress;
        oxSolidAddress = _oxSolidAddress;
        oxSolidRewardsPoolAddress = _oxSolidRewardsPoolAddress;
        oxPoolFactoryAddress = address(this);
        tokensAllowlist = _tokensAllowlist;
        solidlyLensAddress = _solidlyLensAddress;
        solidlyLens = ISolidlyLens(solidlyLensAddress);
        voter = IVoter(solidlyLens.voterAddress());
        voterProxyAddress = _voterProxyAddress;
        vlOxdAddress = _vlOxdAddress;
    }

    /*******************************************************
     *                   oxPool sync mechanism
     *******************************************************/

    /**
     * @notice Fetch unsynced oxPools length
     */
    function unsyncedPoolsLength() public view returns (uint256) {
        uint256 _poolsLength = poolsLength();
        uint256 _unsyncedPoolsLength = _poolsLength - syncedPoolsLength;
        return _unsyncedPoolsLength;
    }

    /**
     * @notice Fetch the number of Solidly pools
     */
    function poolsLength() public view returns (uint256) {
        return solidlyLens.poolsLength();
    }

    /**
     * @notice Fetch the number of synced oxPools
     */
    function oxPoolsLength() public view returns (uint256) {
        return oxPools.length;
    }

    /**
     * @notice Sync all oxPools
     */
    function syncPools() external {
        syncPools(unsyncedPoolsLength());
    }

    /**
     * @notice Sync n number of oxPools
     * @param numberOfPoolsToSync Number of pools to sync
     */
    function syncPools(uint256 numberOfPoolsToSync) public {
        // Don't try to sync more pools than exist
        uint256 unsyncedPoolsLength = unsyncedPoolsLength();
        if (numberOfPoolsToSync > unsyncedPoolsLength) {
            numberOfPoolsToSync = unsyncedPoolsLength;
        }
        uint256 syncTargetLength = syncedPoolsLength + numberOfPoolsToSync;

        // For every unsynced Solidly pool
        for (
            uint256 unsyncedPoolIdx = syncedPoolsLength;
            unsyncedPoolIdx < syncTargetLength;
            unsyncedPoolIdx++
        ) {
            // Create a new oxPool
            address solidPoolAddress = voter.pools(unsyncedPoolIdx);
            string memory solidPoolSymbol = IPool(solidPoolAddress).symbol();
            string memory solidPoolName = IPool(solidPoolAddress).name();
            string memory oxPoolSymbol = string(
                abi.encodePacked("ox-", solidPoolSymbol)
            );
            string memory oxPoolName = string(
                abi.encodePacked("Ox - ", solidPoolName)
            );
            (address oxPoolAddress, ) = createPoolAndMultiRewards(
                solidPoolAddress,
                oxPoolName,
                oxPoolSymbol
            );

            // Add new oxPool to oxPools[] and increment synced length
            oxPools.push(oxPoolAddress);
            oxPoolBySolidPool[solidPoolAddress] = oxPoolAddress;
            solidPoolByOxPool[oxPoolAddress] = solidPoolAddress;
            syncedPoolsLength++;
        }
    }

    /**
     * @notice Create oxPool and multirewards contracts
     */
    function createPoolAndMultiRewards(
        address solidPoolAddress,
        string memory oxPoolName,
        string memory oxPoolSymbol
    ) internal returns (address oxPoolAddress, address stakingAddress) {
        oxPoolAddress = _cloneWithTemplateAddress(oxPoolProxyTemplateAddress);
        IOxPoolProxy(oxPoolAddress).initialize(
            oxPoolImplementationSourceAddress
        );

        stakingAddress = _cloneWithTemplateAddress(multiRewardsTemplateAddress);
        address bribeAddress = solidlyLens.bribeAddresByPoolAddress(
            solidPoolAddress
        );

        // Initialize multirewards
        IMultiRewards(stakingAddress).initialize(
            rewardsDistributorAddress,
            oxPoolAddress
        );

        // Initialize oxPool
        IOxPool(oxPoolAddress).initialize(
            oxPoolFactoryAddress,
            solidPoolAddress,
            stakingAddress,
            oxPoolName,
            oxPoolSymbol,
            bribeAddress,
            tokensAllowlist
        );
    }

    /*******************************************************
     *                    Helper utilities
     *******************************************************/

    /**
     * @notice Clones using EIP-1167 template
     */
    function _cloneWithTemplateAddress(address templateAddress)
        internal
        returns (address poolAddress)
    {
        bytes20 _templateAddress = bytes20(templateAddress);
        assembly {
            let clone := mload(0x40)
            mstore(
                clone,
                0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000000000000000000000
            )
            mstore(add(clone, 0x14), _templateAddress)
            mstore(
                add(clone, 0x28),
                0x5af43d82803e903d91602b57fd5bf30000000000000000000000000000000000
            )
            poolAddress := create(0, clone, 0x37)
        }
    }

    /**
     * @notice Determine whether or not a pool is an oxPool
     */
    function isOxPool(address oxPoolAddress) external view returns (bool) {
        return solidPoolByOxPool[oxPoolAddress] != address(0);
    }
}
