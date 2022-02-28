// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

/**
 * @title Cascading fallback proxy
 * @author 0xDAO
 * @notice Allows users to set multiple proxy implementations while avoiding storage slot collisions
 * @dev Each implementation method signature should be unqiue
 * @dev If implementation method signatures are not unique the first non-reverting implementation for a given call will be used
 * @dev Setting implementation addresses should be permissioned (only owner can set implementations)
 */
contract CascadingFallbackProxy {
    bytes32 internal constant IMPLEMENTATIONS_SLOT =
        0x8774d3970136e4d8780bb894334d371fb20756f5e5be939731251aba00226f30; // keccak256("fallbackproxy.implementations")

    /**
     * @notice Fetch number of implementations
     * @return _implementationsLength Returns number of implementations
     * @dev To do this we read the array length (slot + 0x00) from IMPLEMENTATIONS_SLOT slot
     */
    function implementationsLength()
        public
        view
        returns (uint256 _implementationsLength)
    {
        assembly {
            _implementationsLength := sload(IMPLEMENTATIONS_SLOT)
        }
    }

    /**
     * @notice Fetch implementation address given an index
     * @param _index Index of implementation address
     * @return _implementationAddress Returns the address of the implementation at the specified index
     */
    function implementationByIndex(uint256 _index)
        public
        view
        returns (address _implementationAddress)
    {
        assembly {
            mstore(0, IMPLEMENTATIONS_SLOT)
            _implementationAddress := sload(add(keccak256(0, 0x20), _index))
        }
    }

    /**
     * @notice Fetch a list of all implementation addresses
     * @return _implementationsAddresses Returns an array of implementation addresses
     */
    function implementationsAddresses()
        external
        view
        returns (address[] memory _implementationsAddresses)
    {
        uint256 _implementationsLength = implementationsLength();
        _implementationsAddresses = new address[](_implementationsLength);
        for (
            uint256 implementationIndex;
            implementationIndex < _implementationsAddresses.length;
            implementationIndex++
        ) {
            _implementationsAddresses[
                implementationIndex
            ] = implementationByIndex(implementationIndex);
        }
    }

    /**
     * @notice Add an implementation and increment implementations length
     * @param _implementationAddress Implementation address to add
     */
    function _addImplementation(address _implementationAddress) internal {
        uint256 _implementationsLength = implementationsLength();
        assembly {
            // Store new implementation
            mstore(0, IMPLEMENTATIONS_SLOT)
            let newSlot := add(keccak256(0, 0x20), _implementationsLength)
            sstore(newSlot, _implementationAddress)

            // Increase length
            sstore(IMPLEMENTATIONS_SLOT, add(_implementationsLength, 1))
        }
    }

    /**
     * @notice Set implementation addresses
     * @param _implementationsAddresses The implementation addresses to set
     */
    function _setImplementations(address[] memory _implementationsAddresses)
        internal
    {
        assembly {
            sstore(IMPLEMENTATIONS_SLOT, 0)
        }
        for (
            uint256 implementationIndex;
            implementationIndex < _implementationsAddresses.length;
            implementationIndex++
        ) {
            _addImplementation(_implementationsAddresses[implementationIndex]);
        }
    }

    /**
     * @notice Cascading fallback proxy implementation
     * @dev Iterate through implementations and attempt to execute calldata against each implementation
     * @dev Once a non-reverting method call succeeds stop iterating and return the result
     * @dev If no implementations are found revert
     */
    fallback() external {
        for (uint256 i = 0; i < implementationsLength(); i++) {
            address implementationAddress = implementationByIndex(i);
            assembly {
                let _target := implementationAddress
                calldatacopy(0, 0, calldatasize())
                let success := delegatecall(
                    gas(),
                    _target,
                    0,
                    calldatasize(),
                    0,
                    0
                )
                let returnDataSize := returndatasize()
                returndatacopy(0, 0, returnDataSize)
                if success {
                    return(0, returnDataSize)
                }
                if gt(returnDataSize, 0) {
                    revert(0, returnDataSize)
                }
            }
        }
        revert("CascadingFallbackProxy: Failed to find method");
    }
}
