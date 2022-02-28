// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "./UserProxyStorageLayout.sol";
import "./CascadingFallbackProxy.sol";

/**
 * @title UserProxyTemplate
 * @author 0xDAO
 * @notice UserProxyTemplate is the base implementation of UserProxy
 * @dev Implements a cascading fallback proxy pattern to allow UserProxy to have many implementations
 *      while avoiding maximum contract size limitations
 * @dev Supports call and delegatecall (onlyOwner)
 * @dev Users have complete custody of their proxies
 * @dev Any upgrades to UserProxy are opt-in
 */
contract UserProxyTemplate is UserProxyStorageLayout, CascadingFallbackProxy {
    using SafeERC20 for IERC20;

    /**************************************************
     *                   Initialization
     **************************************************/
    function initialize(
        address _ownerAddress,
        address _userProxyInterfaceAddress,
        address _oxLensAddress,
        address[] memory _implementationsAddresses
    ) public {
        require(oxLensAddress == address(0), "Already initialized");
        ownerAddress = _ownerAddress;
        oxLensAddress = _oxLensAddress;
        oxLens = IOxLens(_oxLensAddress);
        oxSolidAddress = oxLens.oxSolidAddress();
        oxSolidRewardsPoolAddress = oxLens.oxSolidRewardsPoolAddress();
        userProxyInterfaceAddress = _userProxyInterfaceAddress;
        vlOxdAddress = oxLens.vlOxdAddress();
        userProxy = IUserProxy(address(this));
        _setImplementations(_implementationsAddresses);
    }

    modifier onlyOwner() {
        require(msg.sender == ownerAddress, "Only user proxy owner is allowed");
        _;
    }

    function setImplementations(address[] memory implementationsAddresses)
        public
        onlyOwner
    {
        _setImplementations(implementationsAddresses);
    }

    /**************************************************
     *                    Execution
     **************************************************/
    enum Operation {
        Call,
        DelegateCall
    }

    /**
     * @notice Allow UserProxy owners to have complete control over their proxy
     * @param to The target address
     * @param value The amount of gas token to send with the transaction
     * @param data Raw input data
     * @param operation CALL or DELEGATECALL
     * @dev This feature is added as an emergency backstop.
     * @dev UserProxy permissions are scoped to each user.
     * @dev Each UserProxy can only interact with positions for the corresponding account
     * @dev UserProxy permissions are completely isolated in the ecosystem.
     * @dev In practice this feature is equivalent to MakerDAO's DSProxy pattern.
     */
    function execute(
        address to,
        uint256 value,
        bytes calldata data,
        Operation operation
    ) external onlyOwner returns (bool success) {
        if (operation == Operation.Call) success = executeCall(to, value, data);
        else if (operation == Operation.DelegateCall)
            success = executeDelegateCall(to, data);
        require(success == true, "Transaction failed");
    }

    /**
     * @notice Execute an arbitrary call from the context of this contract
     * @param to The target address
     * @param value The amount of gas token to send with the transaction
     * @param data Raw input data
     */
    function executeCall(
        address to,
        uint256 value,
        bytes memory data
    ) internal returns (bool success) {
        assembly {
            success := call(
                gas(),
                to,
                value,
                add(data, 0x20),
                mload(data),
                0,
                0
            )
            let returnDataSize := returndatasize()
            returndatacopy(0, 0, returnDataSize)
            switch success
            case 0 {
                revert(0, returnDataSize)
            }
            default {
                return(0, returnDataSize)
            }
        }
    }

    /**
     * @notice Execute a delegateCall from the context of this contract
     * @param to The target address
     * @param data Raw input data
     */
    function executeDelegateCall(address to, bytes memory data)
        internal
        returns (bool success)
    {
        assembly {
            success := delegatecall(
                gas(),
                to,
                add(data, 0x20),
                mload(data),
                0,
                0
            )
            let returnDataSize := returndatasize()
            returndatacopy(0, 0, returnDataSize)
            switch success
            case 0 {
                revert(0, returnDataSize)
            }
            default {
                return(0, returnDataSize)
            }
        }
    }

    /**************************************************
     *                  Helper Utilities
     **************************************************/
    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }
}
