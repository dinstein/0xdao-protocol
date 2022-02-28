// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

interface IProxy {
    function initialize(address) external;
}

contract OxdDeployer {
    address ownerAddress;

    constructor() {
        ownerAddress = msg.sender;
    }

    function setOwnerAddress(address _ownerAddress) external {
        require(msg.sender == ownerAddress, "Only owner");
    }

    function deploy(
        address ownerAddress,
        bytes memory code,
        uint256 salt
    ) public {
        require(msg.sender == ownerAddress, "Only owner");
        address addr;
        assembly {
            addr := create2(0, add(code, 0x20), mload(code), salt)
            if iszero(extcodesize(addr)) {
                revert(0, 0)
            }
        }
        IProxy(addr).initialize(ownerAddress);
    }

    function deployMany(
        address ownerAddress,
        bytes memory code,
        uint256[] memory salts
    ) public {
        for (uint256 saltIndex; saltIndex < salts.length; saltIndex++) {
            uint256 salt = salts[saltIndex];
            deploy(ownerAddress, code, salt);
        }
    }

    function generateContractAddress(bytes memory bytecode, uint256 salt)
        public
        view
        returns (address)
    {
        bytes32 hash = keccak256(
            abi.encodePacked(
                bytes1(0xff),
                address(this),
                salt,
                keccak256(bytecode)
            )
        );
        return address(uint160(uint256(hash)));
    }
}
