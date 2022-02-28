// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./UserProxyStorageLayout.sol";

/**
 * @title UserProxyLpInteractions
 * @author 0xDAO
 * @notice Core logic for all user LP interactions
 * @dev All implementations must inherit from UserProxyStorageLayout
 */
contract UserProxyLpInteractions is UserProxyStorageLayout {
    using SafeERC20 for IERC20;

    /*******************************************************
     *                     LP Interactions
     *******************************************************/

    // Modifiers
    modifier onlyUserProxyInterfaceOrOwner() {
        require(
            msg.sender == userProxyInterfaceAddress ||
                msg.sender == ownerAddress ||
                msg.sender == address(userProxy),
            "Only user proxy interface or owner is allowed"
        );
        _;
    }
    modifier syncPools() {
        oxLens.oxPoolFactory().syncPools(1);
        _;
    }
    modifier syncSolidEmissions(address solidPoolAddress) {
        address gaugeAddress = oxLens.gaugeBySolidPool(solidPoolAddress);

        _;
    }

    /**
     * @notice LP -> oxPool LP -> Staked
     * @param solidPoolAddress The solid pool LP address to deposit
     * @param amount The amount of solid pool LP to deposit
     */
    function depositLpAndStake(address solidPoolAddress, uint256 amount)
        external
        onlyUserProxyInterfaceOrOwner
        syncPools
    {
        // No empty deposits
        require(amount > 0, "Deposit amount must be greater than zero");

        // Deposit Solidly LP
        IERC20(solidPoolAddress).transferFrom(
            msg.sender,
            address(this),
            amount
        );

        // Transfer Solidly LP to ox pool to receive Ox pool LP receipt token
        address oxPoolAddress = oxLens.oxPoolBySolidPool(solidPoolAddress);
        IERC20(solidPoolAddress).approve(oxPoolAddress, amount);
        IOxPool(oxPoolAddress).depositLp(amount);

        // Save staking balance
        address stakingAddress = IOxPool(oxPoolAddress).stakingAddress();
        uint256 stakingBalanceBefore = IERC20(stakingAddress).balanceOf(
            address(this)
        );

        // Stake oxLP in multirewards
        IERC20(oxPoolAddress).approve(stakingAddress, amount);
        IMultiRewards(stakingAddress).stake(amount);
        uint256 stakingBalanceAfter = IERC20(stakingAddress).balanceOf(
            address(this)
        );

        // Make sure staking balance increased
        assert(stakingBalanceAfter == stakingBalanceBefore + amount);

        // Register deposit
        registerStake(stakingAddress);
    }

    /**
     * @notice LP -> oxPool LP
     * @param solidPoolAddress The solid pool LP address to deposit
     * @param amount The amount of solid pool LP to deposit
     */
    function depositLp(address solidPoolAddress, uint256 amount)
        external
        onlyUserProxyInterfaceOrOwner
        syncPools
        syncSolidEmissions(solidPoolAddress)
    {
        // No empty deposits
        require(amount > 0, "Deposit amount must be greater than zero");

        // Deposit Solidly LP
        IERC20(solidPoolAddress).transferFrom(
            msg.sender,
            address(this),
            amount
        );

        // Transfer Solidly LP to ox pool to receive Ox pool LP receipt token
        address oxPoolAddress = oxLens.oxPoolBySolidPool(solidPoolAddress);
        IERC20(solidPoolAddress).approve(oxPoolAddress, amount);
        IOxPool(oxPoolAddress).depositLp(amount);

        // Transfer oxPool LP to user
        IERC20(oxPoolAddress).transfer(ownerAddress, amount);
    }

    /**
     * @notice Staked oxPool LP -> oxPool LP -> LP
     * @param solidPoolAddress The solid pool LP address to withdraw and unstake
     * @param amount The amount of solid pool LP to withdraw and unstake
     */
    function unstakeLpAndWithdraw(
        address solidPoolAddress,
        uint256 amount,
        bool claimRewards
    ) public onlyUserProxyInterfaceOrOwner {
        // No empty withdrawals
        require(amount > 0, "Withdrawal amount must be greater than zero");

        // Fetch addresses
        address oxPoolAddress = oxLens.oxPoolBySolidPool(solidPoolAddress);
        address stakingAddress = IOxPool(oxPoolAddress).stakingAddress();

        // Check staked balance
        uint256 stakedBalance = IERC20(stakingAddress).balanceOf(address(this));
        require(stakedBalance > 0, "Nothing to withdraw");

        // Withdraw oxLP from multirewards
        IMultiRewards(stakingAddress).withdraw(amount);

        // Redeem/burn oxPool LP for Solidly LP
        IOxPool(oxPoolAddress).withdrawLp(amount);

        // Transfer Solidly LP to user
        IERC20(solidPoolAddress).transfer(ownerAddress, amount);

        // Register withdrawal
        registerUnstake(stakingAddress);

        // Claim multirewards
        if (claimRewards) {
            userProxy.claimStakingRewards(stakingAddress);
        }
    }

    /**
     * @notice oxPool LP -> LP
     * @param solidPoolAddress The solid pool LP address to withdraw
     * @param amount The amount of solid pool LP to withdraw
     */
    function withdrawLp(address solidPoolAddress, uint256 amount)
        external
        onlyUserProxyInterfaceOrOwner
        syncPools
        syncSolidEmissions(solidPoolAddress)
    {
        // No empty withdrawals
        require(amount > 0, "Withdrawal amount must be greater than zero");

        // Fetch addresses
        address oxPoolAddress = oxLens.oxPoolBySolidPool(solidPoolAddress);

        // Receive oxPool LP from msg.sender
        IERC20(oxPoolAddress).transferFrom(msg.sender, address(this), amount);

        // Burn oxPool LP for Solidly LP
        IOxPool(oxPoolAddress).withdrawLp(amount);

        // Transfer Solidly LP to user
        IERC20(solidPoolAddress).transfer(ownerAddress, amount);
    }

    /**
     * @notice oxPool LP -> Staked oxPool LP
     * @param oxPoolAddress The oxPool LP address to stake
     * @param amount The amount of oxPool LP to stake
     */
    function stakeOxLp(address oxPoolAddress, uint256 amount)
        external
        onlyUserProxyInterfaceOrOwner
        syncPools
    {
        // No empty staking
        require(amount > 0, "Staking amount must be greater than zero");

        // Save staked balance
        address stakingAddress = IOxPool(oxPoolAddress).stakingAddress();
        uint256 stakedBalanceBefore = IERC20(stakingAddress).balanceOf(
            address(this)
        );

        // Stake oxPool LP
        IERC20(oxPoolAddress).transferFrom(msg.sender, address(this), amount);

        // Stake oxLP in multirewards
        IERC20(oxPoolAddress).approve(stakingAddress, amount);
        IMultiRewards(stakingAddress).stake(amount);

        // Make sure balance was staked
        uint256 stakedBalanceAfter = IERC20(stakingAddress).balanceOf(
            address(this)
        );
        assert(stakedBalanceAfter == stakedBalanceBefore + amount);

        // Register deposit
        registerStake(stakingAddress);
    }

    /**
     * @notice Staked oxPool LP -> oxPool LP
     * @param oxPoolAddress The oxPool LP address to unstake
     * @param amount The amount of oxPool LP to unstake
     */
    function unstakeOxLp(address oxPoolAddress, uint256 amount)
        external
        onlyUserProxyInterfaceOrOwner
        syncPools
    {
        // No empty unstaking
        require(amount > 0, "Staking amount must be greater than zero");

        // Save staked balance
        address stakingAddress = IOxPool(oxPoolAddress).stakingAddress();
        uint256 stakedBalanceBefore = IERC20(stakingAddress).balanceOf(
            address(this)
        );

        // Withdraw oxLP from multirewards
        IMultiRewards(stakingAddress).withdraw(amount);

        // Make sure balance was unstaked
        uint256 stakedBalanceAfter = IERC20(stakingAddress).balanceOf(
            address(this)
        );
        assert(stakedBalanceAfter == stakedBalanceBefore - amount);

        // Transfer oxPool LP to user
        IERC20(oxPoolAddress).transfer(ownerAddress, amount);

        // Register withdrawal
        registerUnstake(stakingAddress);
    }

    /**
     * @notice Claim staking rewards given a staking pool address
     * @param stakingPoolAddress Address of MultiRewards contract
     */
    function claimStakingRewards(address stakingPoolAddress)
        public
        onlyUserProxyInterfaceOrOwner
    {
        IMultiRewards multiRewards = IMultiRewards(stakingPoolAddress);
        multiRewards.getReward();
        uint256 rewardTokensLength = multiRewards.rewardTokensLength();
        for (
            uint256 rewardTokenIndex;
            rewardTokenIndex < rewardTokensLength;
            rewardTokenIndex++
        ) {
            address rewardTokenAddress = multiRewards.rewardTokens(
                rewardTokenIndex
            );
            uint256 balance = IERC20(rewardTokenAddress).balanceOf(
                address(this)
            );
            if (balance > 0) {
                IERC20(rewardTokenAddress).safeTransfer(ownerAddress, balance);
            }
        }

        // Register unstake (user will only be unstaked if they have no earnings or balance)
        registerUnstake(stakingPoolAddress);
    }

    /**
     * @notice Claim all LP rewards
     */
    function claimStakingRewards() external onlyUserProxyInterfaceOrOwner {
        for (
            uint256 stakingPoolIndex;
            stakingPoolIndex < stakingPoolsLength;
            stakingPoolIndex++
        ) {
            claimStakingRewards(stakingAddressByIndex[stakingPoolIndex]);
        }
    }

    /**
     * @notice Claim rewards given an array of staking pools addresses
     * @param stakingPoolsAddresses An array of MultiRewards contract addresses
     */
    function claimStakingRewards(address[] memory stakingPoolsAddresses)
        public
        onlyUserProxyInterfaceOrOwner
    {
        for (
            uint256 stakingPoolIndex;
            stakingPoolIndex < stakingPoolsAddresses.length;
            stakingPoolIndex++
        ) {
            address stakingPoolAddress = stakingPoolsAddresses[
                stakingPoolIndex
            ];
            claimStakingRewards(stakingPoolAddress);
        }
    }

    /**
     * @notice Save LP stake in user stake registry
     * @param stakingAddress Staking address to register
     */
    function registerStake(address stakingAddress) internal {
        if (!hasStake[stakingAddress]) {
            hasStake[stakingAddress] = true;
            stakingAddressByIndex[stakingPoolsLength] = stakingAddress;
            indexByStakingAddress[stakingAddress] = stakingPoolsLength;
            stakingPoolsLength++;
        }
    }

    /**
     * @notice Save LP unstake in user stake registry
     * @param stakingAddress Staking address to unregister
     */
    function registerUnstake(address stakingAddress) internal {
        IMultiRewards multiRewards = IMultiRewards(stakingAddress);
        uint256 balanceOfStakingAddress = multiRewards.balanceOf(address(this));

        // Check to see if account has any earnings
        bool earned;
        IUserProxy.RewardToken[] memory rewardTokens = oxLens
            .rewardTokensPositionsOf(ownerAddress, stakingAddress);
        for (
            uint256 rewardTokenIndex;
            rewardTokenIndex < rewardTokens.length;
            rewardTokenIndex++
        ) {
            IUserProxy.RewardToken memory rewardToken = rewardTokens[
                rewardTokenIndex
            ];
            if (rewardToken.earned > 0) {
                earned = true;
                break;
            }
        }

        // Only unregister if user has no earnings or balance
        if (
            balanceOfStakingAddress == 0 && !earned && hasStake[stakingAddress]
        ) {
            hasStake[stakingAddress] = false;
            uint256 stakeIndex = indexByStakingAddress[stakingAddress];
            address latestStake = stakingAddressByIndex[stakingPoolsLength - 1];
            stakingAddressByIndex[stakeIndex] = latestStake;
            stakingPoolsLength--;
        }
    }

    /**
     * @notice Fetch a list of all staked addresses for this user
     */
    function stakingAddresses() public view returns (address[] memory) {
        address[] memory _stakedAddresses = new address[](stakingPoolsLength);
        for (
            uint256 stakeIndex;
            stakeIndex < stakingPoolsLength;
            stakeIndex++
        ) {
            _stakedAddresses[stakeIndex] = stakingAddressByIndex[stakeIndex];
        }
        return _stakedAddresses;
    }
}
