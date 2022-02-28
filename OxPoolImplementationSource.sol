// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

/**
 * @title Slightly modified version of 0xDAO proxy to allow oxPool implementations to be updated
 * @author 0xDAO
 * @notice oxPool upgrading can be disabled by killing governance
 * @dev Does not implement a proxy fallback mechanism as this contract is only intended to provide source implementation address for oxPools
 */
contract OxPoolImplementationSource {
    bytes32 constant IMPLEMENTATION_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc; // keccak256('eip1967.proxy.implementation')
    bytes32 constant GOVERNANCE_SLOT =
        0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103; // keccak256('eip1967.proxy.admin')
    bytes32 constant INITIALIZED_SLOT =
        0x834ce84547018237034401a09067277cdcbe7bbf7d7d30f6b382b0a102b7b4a3; // keccak256('eip1967.proxy.initialized')

    /**
     * @notice Initialize governance (this can only be done once)
     * @param _governanceAddress New governance address
     */
    function initializeProxyStorage(address _governanceAddress) public {
        bool initialized;
        assembly {
            initialized := sload(INITIALIZED_SLOT)
            if eq(initialized, 1) {
                revert(0, 0)
            }
            sstore(INITIALIZED_SLOT, 1)
            sstore(GOVERNANCE_SLOT, _governanceAddress)
        }
    }

    /**
     * @notice Fetch proxyStorageInitialized status
     * @return _initialized Returns the current initialization status
     */
    function proxyStorageInitialized()
        external
        view
        returns (bool _initialized)
    {
        assembly {
            _initialized := sload(INITIALIZED_SLOT)
        }
    }

    /**
     * @notice Detect whether or not governance is killed
     * @return Return true if governance is killed, false if not
     * @dev If governance is killed this contract becomes immutable
     */
    function governanceIsKilled() external view returns (bool) {
        return governanceAddress() == address(0);
    }

    /**
     * @notice Kill governance, making this contract immutable
     * @dev Only governance can kil governance
     */
    function killGovernance() external {
        require(msg.sender == governanceAddress(), "Only governance");
        updateGovernanceAddress(address(0));
    }

    /**
     * @notice Update implementation address
     * @param _implementationAddress Address of the new implementation
     * @dev Only governance can update implementation
     */
    function updateImplementationAddress(address _implementationAddress)
        external
    {
        require(msg.sender == governanceAddress(), "Only governance");
        assembly {
            sstore(IMPLEMENTATION_SLOT, _implementationAddress)
        }
    }

    /**
     * @notice Update governance address
     * @param _governanceAddress New governance address
     * @dev Only governance can update governance
     */
    function updateGovernanceAddress(address _governanceAddress) public {
        require(msg.sender == governanceAddress(), "Only governance");
        assembly {
            sstore(GOVERNANCE_SLOT, _governanceAddress)
        }
    }

    /**
     * @notice Fetch the current implementation address
     * @return _implementationAddress Returns the current implementation address
     */
    function implementationAddress()
        external
        view
        returns (address _implementationAddress)
    {
        assembly {
            _implementationAddress := sload(IMPLEMENTATION_SLOT)
        }
    }

    /**
     * @notice Fetch current governance address
     * @return _governanceAddress Returns current governance address
     */
    function governanceAddress()
        public
        view
        returns (address _governanceAddress)
    {
        assembly {
            _governanceAddress := sload(GOVERNANCE_SLOT)
        }
    }
}
