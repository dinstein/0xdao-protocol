// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

interface IVoter {
    function isWhitelisted(address) external view returns (bool);

    function length() external view returns (uint256);

    function pools(uint256) external view returns (address);

    function gauges(address) external view returns (address);

    function bribes(address) external view returns (address);

    function factory() external view returns (address);

    function gaugefactory() external view returns (address);

    function vote(
        uint256,
        address[] memory,
        int256[] memory
    ) external;

    function updateFor(address[] memory _gauges) external;

    function claimRewards(address[] memory _gauges, address[][] memory _tokens)
        external;

    function distribute(address _gauge) external;
}
