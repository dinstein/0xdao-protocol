// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "./UserProxyStorageLayout.sol";

/**
 * @title UserProxyNftInteractions
 * @author 0xDAO
 * @notice Core logic for all user SOLID/veNFT interactions
 * @dev All implementations must inherit from UserProxyStorageLayout
 */
contract UserProxyNftInteractions is UserProxyStorageLayout {
    using SafeERC20 for IERC20;

    /*******************************************************
     *                 SOLID and veNFT interactions
     *******************************************************/

    // Modifiers
    modifier syncPools() {
        oxLens.oxPoolFactory().syncPools(1);
        _;
    }
    modifier onlyUserProxyInterfaceOrOwner() {
        require(
            msg.sender == userProxyInterfaceAddress ||
                msg.sender == ownerAddress ||
                msg.sender == address(userProxy),
            "Only user proxy interface or owner is allowed"
        );
        _;
    }

    /**
     * @notice SOLID -> veNFT -> oxSOLID
     * @param amount The amount of SOLID to convert to oxSOLID
     */
    function convertSolidToOxSolid(uint256 amount)
        external
        onlyUserProxyInterfaceOrOwner
        syncPools
    {
        // No empty converting
        require(amount > 0, "Amount to convert must be greater than zero");

        // Lock SOLID
        uint256 tokenId = _lockSolid(amount);

        // Convert NFT to oxSOLID
        _convertNftToOxSolid(tokenId);

        // Transfer oxSOLID to owner
        oxLens.oxSolid().transfer(ownerAddress, amount);
    }

    /**
     * @notice Convert veNFT to oxSOLID
     * @param tokenId The tokenID to convert
     */
    function _convertNftToOxSolid(uint256 tokenId) internal {
        // Fetch oxSOLID balanceOf(owner) before conversions
        uint256 oxSolidBalanceOfBefore = oxLens.oxSolid().balanceOf(
            address(this)
        );

        // Determine amount of oxSOLID to mint
        IVe ve = oxLens.ve();
        uint256 amount = ve.locked(tokenId);
        assert(amount > 0);

        // Deposit NFT to oxSOLID and receive oxSOLID
        ve.approve(oxSolidAddress, tokenId);
        oxLens.oxSolid().convertNftToOxSolid(tokenId);

        // Make sure correct amount of oxSOLID was received
        uint256 oxSolidBalanceOfAfter = oxLens.oxSolid().balanceOf(
            address(this)
        );
        assert(oxSolidBalanceOfAfter == oxSolidBalanceOfBefore + amount);
    }

    /**
     * @notice Lock SOLID
     * @param amount The amount of SOLID to lock
     * @return tokenId The newly minted tokenID
     */
    function _lockSolid(uint256 amount) internal returns (uint256 tokenId) {
        // No empty locking
        require(amount > 0, "Amount to lock must be greater than zero");

        // Receive SOLID from msg.sender
        ISolid solid = oxLens.solid();
        solid.transferFrom(msg.sender, address(this), amount);

        // Allow ve to spend SOLID
        address veAddress = oxLens.veAddress();
        solid.approve(veAddress, amount);

        // Lock SOLID (SOLID -> veNFT)
        uint256 lockTime = 4 * 365 * 86400; // 4 years
        tokenId = oxLens.ve().create_lock(amount, lockTime);
    }

    /**
     * @notice SOLID -> veNFT -> oxSOLID -> Staked oxSOLID
     * @param amount The amount of SOLID to convert and stake
     */
    function convertSolidToOxSolidAndStake(uint256 amount)
        external
        onlyUserProxyInterfaceOrOwner
        syncPools
    {
        // No empty converting
        require(amount > 0, "Amount to convert must be greater than zero");

        // Lock SOLID
        uint256 tokenId = _lockSolid(amount);

        // Convert NFT to oxSOLID
        _convertNftToOxSolid(tokenId);

        // Stake oxSOLID
        _stakeOxSolid(amount);
    }

    /**
     * @notice veNFT -> oxSOLID
     * @param tokenId The tokenId to convert
     */
    function convertNftToOxSolid(uint256 tokenId)
        public
        onlyUserProxyInterfaceOrOwner
        syncPools
    {
        // Amount of underlying SOLID locked
        IVe ve = oxLens.ve();
        uint256 amount = ve.locked(tokenId);

        // Transfer NFT to this contract
        ve.safeTransferFrom(msg.sender, address(this), tokenId);

        // Perform actual conversion
        _convertNftToOxSolid(tokenId);

        // Send oxSOLID to user
        oxLens.oxSolid().transfer(ownerAddress, amount);
    }

    /**
     * @notice veNFT -> oxSOLID -> Staked oxSOLID
     * @param tokenId The tokenId to convert and stake
     */
    function convertNftToOxSolidAndStake(uint256 tokenId)
        public
        onlyUserProxyInterfaceOrOwner
        syncPools
    {
        // Amount of underlying SOLID locked
        IVe ve = oxLens.ve();
        uint256 amount = ve.locked(tokenId);

        // Transfer NFT to this contract
        ve.safeTransferFrom(msg.sender, address(this), tokenId);

        // Perform actual conversion
        _convertNftToOxSolid(tokenId);

        // Stake oxSOLID
        _stakeOxSolid(amount);
    }

    /**
     * @notice Stake oxSOLID in rewards pool
     */
    function _stakeOxSolid(uint256 amount) internal {
        address stakingAddress;

        // Determine partner status
        bool isPartner = oxLens.isPartner(address(this));

        // Set staking address
        if (isPartner) {
            stakingAddress = oxLens.partnersRewardsPoolAddress();
        } else {
            stakingAddress = oxSolidRewardsPoolAddress;
        }

        // Allow oxSOLID mutlirewards to spend oxSOLID
        oxLens.oxSolid().approve(stakingAddress, amount);

        // Stake oxSOLID in multirewards
        IMultiRewards(stakingAddress).stake(amount);
    }

    /**
     * @notice oxSOLID -> staked oxSOLID
     */
    function stakeOxSolid(uint256 amount)
        public
        onlyUserProxyInterfaceOrOwner
        syncPools
    {
        // Transfer oxSOLID from msg.sender to UserProxy
        oxLens.oxSolid().transferFrom(msg.sender, address(this), amount);

        // Stake oxSOLID on behalf of user
        _stakeOxSolid(amount);
    }

    /**
     * oxSOLID -> staked oxSOLID (OXD v1 staking contract)
     */
    function stakeOxSolidInOxdV1(uint256 amount)
        public
        onlyUserProxyInterfaceOrOwner
        syncPools
    {
        // Transfer oxSOLID from msg.sender to UserProxy
        oxLens.oxSolid().transferFrom(msg.sender, address(this), amount);

        // Stake oxSOLID on behalf of user
        _stakeOxSolidInOxdV1(amount);
    }

    /**
     * @notice Perform oxSOLID stake into v1 staking pool
     */
    function _stakeOxSolidInOxdV1(uint256 amount) internal {
        address stakingAddress = oxLens.oxdV1RewardsAddress();

        // Allow oxSOLID mutlirewards to spend oxSOLID
        oxLens.oxSolid().approve(stakingAddress, amount);

        // Stake oxSOLID in multirewards
        IMultiRewards(stakingAddress).stake(amount);
    }

    /**
     * @notice Staked oxSOLID -> oxSOLID
     * @param amount The amount of oxSOLID to unstake
     */
    function unstakeOxSolid(uint256 amount)
        public
        onlyUserProxyInterfaceOrOwner
    {
        address stakingAddress;

        // Determine partner status
        bool isPartner = oxLens.isPartner(address(this));

        // Set staking address
        if (isPartner) {
            stakingAddress = oxLens.partnersRewardsPoolAddress();
        } else {
            stakingAddress = oxSolidRewardsPoolAddress;
        }
        unstakeOxSolid(stakingAddress, amount);
    }

    /**
     * @notice Staked oxSOLID (OXD v1 rewards) -> oxSOLID
     * @param amount The amount to unstake
     */
    function unstakeOxSolidInOxdV1(uint256 amount)
        public
        onlyUserProxyInterfaceOrOwner
    {
        unstakeOxSolid(oxLens.oxdV1RewardsAddress(), amount);
    }

    /**
     * @notice Staked oxSOLID -> oxSOLID
     * @param stakingAddress Address to unstake from
     * @param amount The amount to unstake
     */
    function unstakeOxSolid(address stakingAddress, uint256 amount)
        public
        onlyUserProxyInterfaceOrOwner
        syncPools
    {
        // No empty unstaking
        require(amount > 0, "Amount to unstake must be greater than zero");

        // Unstake oxSOLID
        IMultiRewards(stakingAddress).withdraw(amount);

        // Transfer oxSOLID to owner
        oxLens.oxSolid().transfer(ownerAddress, amount);
    }

    /**
     * @notice Redeem OXD v1 for oxSOLID
     */
    function redeemOxdV1(uint256 amount)
        external
        onlyUserProxyInterfaceOrOwner
    {
        IERC20 oxdV1 = IERC20(oxLens.oxdV1Address());
        oxdV1.transferFrom(msg.sender, address(this), amount);

        address oxdV1RedeemAddress = oxLens.oxdV1RedeemAddress();
        IOxdV1Redeem oxdV1Redeem = IOxdV1Redeem(oxdV1RedeemAddress);

        oxdV1.approve(oxdV1RedeemAddress, amount);
        oxdV1Redeem.redeem(amount);

        IMultiRewards oxdV1Rewards = IMultiRewards(
            oxLens.oxdV1RewardsAddress()
        );
        IOxSolid oxSolid = oxLens.oxSolid();
        oxSolid.transfer(ownerAddress, oxSolid.balanceOf(address(this)));

        uint256 rewardTokensLength = oxdV1Rewards.rewardTokensLength();
        for (uint256 i; i < rewardTokensLength; i++) {
            IERC20 rewardToken = IERC20(oxdV1Rewards.rewardTokens(i));
            uint256 balance = rewardToken.balanceOf(address(this));
            if (balance > 0) {
                rewardToken.safeTransfer(ownerAddress, balance);
            }
        }
    }

    /**
     * @notice Redeem OXD v1 for oxSOLID and stake into oxdV1Rewards
     */
    function redeemAndStakeOxdV1(uint256 amount)
        external
        onlyUserProxyInterfaceOrOwner
    {
        //establish vars
        IERC20 oxdV1 = IERC20(oxLens.oxdV1Address());
        IOxSolid oxSolid = oxLens.oxSolid();
        address oxdV1RewardsAddress = oxLens.oxdV1RewardsAddress();
        IOxdV1Rewards oxdV1Rewards = IOxdV1Rewards(oxdV1RewardsAddress);
        address oxdV1RedeemAddress = oxLens.oxdV1RedeemAddress();
        IOxdV1Redeem oxdV1Redeem = IOxdV1Redeem(oxdV1RedeemAddress);

        //transfer OXDv1 to userProxy
        oxdV1.transferFrom(msg.sender, address(this), amount);

        //approve and redeem OXDv1 from oxdV1Redeem
        oxdV1.approve(oxdV1RedeemAddress, amount);
        oxdV1Redeem.redeem(amount);

        //check redeemed oxSOLID balance against stakingCap, transfer excess to owner
        uint256 oxSolidBalance = oxSolid.balanceOf(address(this));
        uint256 stakingCap = oxdV1Rewards.stakingCap(address(this));
        uint256 stakedBalance = oxdV1Rewards.balanceOf(address(this));

        // If capMultiplier is lowered, stakingCap can be lower than stakedBalance
        // Users can withdraw under such conditions, but can't stake more
        if (stakingCap > stakedBalance) {
            if (stakingCap - stakedBalance < oxSolidBalance) {
                uint256 oxSolidToTransfer = oxSolidBalance - stakingCap;
                oxSolid.transfer(ownerAddress, oxSolidToTransfer);
                oxSolidBalance = stakingCap;
            }
        } else {
            // if stakingCap < stakedBalance, transfer all oxSOLID to owner
            oxSolid.transfer(ownerAddress, oxSolidBalance);
            oxSolidBalance = 0;
        }

        //approve and stake oxSOLID in oxdV1Rewards
        if (oxSolidBalance > 0) {
            oxSolid.approve(oxdV1RewardsAddress, oxSolidBalance);
            oxdV1Rewards.stake(oxSolidBalance);
        }

        //transfer misc bribes gotten from redeem to owner
        uint256 rewardTokensLength = oxdV1Rewards.rewardTokensLength();
        for (uint256 i; i < rewardTokensLength; i++) {
            IERC20 rewardToken = IERC20(oxdV1Rewards.rewardTokens(i));
            uint256 balance = rewardToken.balanceOf(address(this));
            if (balance > 0) {
                rewardToken.safeTransfer(ownerAddress, balance);
            }
        }
    }

    /**
     * @notice Migrates nonparters who recently got whitelisted as partners
     */
    function migrateOxSolidToPartner() external onlyUserProxyInterfaceOrOwner {
        IMultiRewards oxSolidRewardsPool = IMultiRewards(
            oxLens.oxSolidRewardsPoolAddress()
        );
        IMultiRewards partnersRewardsPool = IMultiRewards(
            oxLens.partnersRewardsPoolAddress()
        );

        uint256 nonPartnerStakedBalance = oxSolidRewardsPool.balanceOf(
            address(this)
        );
        oxSolidRewardsPool.exit();
        oxLens.oxSolid().approve(
            address(partnersRewardsPool),
            nonPartnerStakedBalance
        );
        partnersRewardsPool.stake(nonPartnerStakedBalance);
    }

    /**
     * @notice Vote lock OXD for 16 weeks (non-transferrable)
     * @param amount Amount of OXD to lock
     * @param spendRatio Spend ratio for OxdLocker
     * @dev OxdLocker utilizes the same code as CvxLocker
     */
    function voteLockOxd(uint256 amount, uint256 spendRatio)
        external
        onlyUserProxyInterfaceOrOwner
    {
        // Receive OXD
        oxLens.oxd().transferFrom(msg.sender, address(this), amount);

        // Allow vlOXD to spend OXD
        oxLens.oxd().approve(vlOxdAddress, amount);

        // Lock OXD
        oxLens.vlOxd().lock(address(this), amount, spendRatio);
        assert(oxLens.vlOxd().lockedBalanceOf(address(this)) > 0);
    }

    /**
     * @notice Withdraw vote locked OXD
     * @param spendRatio Spend ratio
     */
    function withdrawVoteLockedOxd(uint256 spendRatio, bool claim)
        external
        onlyUserProxyInterfaceOrOwner
    {
        uint256 currentBalance = oxLens.vlOxd().lockedBalanceOf(address(this));
        require(currentBalance > 0, "Nothing to withdraw");

        if (claim) {
            // Claim staking rewards and transfer them to proxy owner
            userProxy.claimVlOxdRewards();
        }

        // Withdraw OXD and transfer to owner
        oxLens.vlOxd().processExpiredLocks(false, spendRatio, ownerAddress);
    }

    /**
     * @notice Relock vote locked OXD
     * @param spendRatio Spend ratio
     */
    function relockVoteLockedOxd(uint256 spendRatio)
        external
        onlyUserProxyInterfaceOrOwner
    {
        oxLens.vlOxd().processExpiredLocks(true, spendRatio, address(this));
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

    /**
     * @notice Claim staking rewards given a staking pool address
     * @dev The generalized function doesn't work because vlOXD is a bit different from other multirewards
     */
    function claimVlOxdRewards() public onlyUserProxyInterfaceOrOwner {
        address stakingPoolAddress = oxLens.vlOxdAddress();
        IVlOxd multiRewards = IVlOxd(stakingPoolAddress);
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
            IERC20(rewardTokenAddress).safeTransfer(
                ownerAddress,
                IERC20(rewardTokenAddress).balanceOf(address(this))
            );
        }
    }
}
