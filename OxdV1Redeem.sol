// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Wrapper.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./Governable.sol";
import "./ProxyImplementation.sol";

import "./interfaces/IOxLens.sol";
import "./interfaces/IMultiRewards.sol";

/**
 * @title OXD v1 redemption
 * @author 0xDAO
 */
contract OxdV1Redeem is Governable, ProxyImplementation {
    /*******************************************************
     *                   Configuration
     *******************************************************/

    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Interface helpers
    IMultiRewards public oxdV1Rewards;
    IERC20 public oxdV1;
    IOxLens public oxLens;
    IVoterProxy public voterProxy;
    IOxSolid public oxSolid;
    ISolid public solid;

    // Burning calcs
    mapping(address => uint256) public oxdV1Burnt;
    uint256 public oxdV1SnapshotTotalSupply = 1294802716773849662269150314;
    uint256 public oxdV1veSOLID = 2376588000000000000000000; // 0xDAO veNFT SOLID allocation
    uint256 public basis = 10000;

    // Internal helpers
    address internal deadAddress =
        address(0x000000000000000000000000000000000000dEaD);

    /**
     * @notice Initialize proxy storage
     */
    function initializeProxyStorage(IERC20 _oxdV1, IMultiRewards _oxdV1Rewards)
        public
        checkProxyInitialized
    {
        // From Governable
        governanceAddress = msg.sender;

        oxdV1 = _oxdV1;
        oxdV1Rewards = _oxdV1Rewards;
    }

    /**
     * @notice Initialize
     * @dev Can only be initialized once by governance
     * @param _salt to avoid hash collision with proxy's initialize()
     */
    function initialize(IOxLens _oxLens, bool _salt) external onlyGovernance {
        require(address(oxLens) == address(0), "Already Initialized");
        oxLens = _oxLens;
        voterProxy = oxLens.voterProxy();
        oxSolid = oxLens.oxSolid();
        solid = oxLens.solid();
    }

    /*******************************************************
     *                     Core logic
     *******************************************************/

    /**
     * @notice Allow governance to stake oxSOLID into oxdV1Rewards for OXDv1 holders to redeem against
     * @param amount Amount of oxSOLID to stake
     */
    function stake(uint256 amount) external onlyGovernance {
        oxSolid.transferFrom(msg.sender, address(this), amount);
        _stake(amount);
    }

    /**
     * @notice Stake oxSOLID into oxdV1Rewards for OXDv1 holders to redeem against
     * @param amount Amount of oxSOLID to stake
     */
    function _stake(uint256 amount) internal {
        oxSolid.approve(address(oxdV1Rewards), amount);
        oxdV1Rewards.stake(amount);
    }

    /**
     * @notice Redeem OXDv1 for oxSOLID
     * @param amount Amount of OXDv1 to redeem
     * @dev OXDv1 can't be burnt, will be sending to 0xdead or similar instead
     */
    function redeem(uint256 amount) external {
        // Get "circulating supply" before burning
        uint256 circulatingSupply = oxdV1SnapshotTotalSupply.sub(
            oxdV1.balanceOf(deadAddress)
        );

        // Burn OXD v1
        oxdV1.transferFrom(msg.sender, deadAddress, amount);

        // Get bribes and other rewards, if it's SOLID or oxSOLID, restake. Otherwise, payout.
        oxdV1Rewards.getReward();
        uint256 rewardTokensLength = oxdV1Rewards.rewardTokensLength();
        for (uint256 i; i < rewardTokensLength; i++) {
            address rewardToken = oxdV1Rewards.rewardTokens(i);
            uint256 earned = IERC20(rewardToken).balanceOf(address(this));
            if (earned > 0) {
                if (rewardToken == address(oxSolid)) {
                    _stake(earned);
                } else if (rewardToken == address(solid)) {
                    solid.approve(address(voterProxy), earned);
                    voterProxy.lockSolid(earned);
                    _stake(earned);
                } else {
                    uint256 amountToTransfer = earned.mul(amount).div(
                        circulatingSupply
                    );
                    IERC20(rewardToken).safeTransfer(
                        msg.sender,
                        amountToTransfer
                    );
                }
            }
        }

        // Calculate how much oxSOLID to pay out
        uint256 oxSolidAmount = redeemableOxSolid().mul(amount).div(
            circulatingSupply
        );

        // Withdraw oxSOLID and transfer to redeemer
        oxdV1Rewards.withdraw(oxSolidAmount);
        oxSolid.transfer(msg.sender, oxSolidAmount);
        oxdV1Burnt[msg.sender] += amount;
    }

    /**
     * @notice Fetch total redeemable oxSOLID
     */
    function redeemableOxSolid() public view returns (uint256) {
        return oxdV1Rewards.balanceOf(address(this));
    }
}
