// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Wrapper.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "./interfaces/IOxLens.sol";
import "./interfaces/IUserProxy.sol";
import "./interfaces/IUserProxyFactory.sol";
import "./interfaces/ISolid.sol";
import "./interfaces/IVe.sol";

/**
 * @title UserProxyInterface
 * @author 0xDAO
 * @notice The primary user interface contract for front-end
 * @dev User proxy interface is responsible for creating and fetching a user's proxy
 *      and transferring tokens/routing calls to the user's proxy
 * @dev All calls here are unpermissioned as each call deals only with the proxy for msg.sender
 * @dev Authentication is handled in actual UserProxy implementations
 */
contract UserProxyInterface {
    // Public addresses
    address public userProxyFactoryAddress;
    address public oxLensAddress;

    // Internal interface helpers
    IOxLens internal oxLens;
    IVe internal ve;
    ISolid internal solid;
    IOxSolid internal oxSolid;
    IOxd internal oxd;

    /**
     * @notice Initialize UserProxyInterface
     * @param _userProxyFactoryAddress Factory address
     * @param _oxLensAddress oxLens address
     */
    function initialize(
        address _userProxyFactoryAddress,
        address _oxLensAddress
    ) public {
        require(userProxyFactoryAddress == address(0), "Already initialized");
        userProxyFactoryAddress = _userProxyFactoryAddress;
        oxLensAddress = _oxLensAddress;
        oxLens = IOxLens(_oxLensAddress);
        ve = oxLens.ve();
        solid = oxLens.solid();
        oxSolid = oxLens.oxSolid();
        oxd = oxLens.oxd();
    }

    /*******************************************************
     *                    LP Interactions
     *******************************************************/

    /**
     * @notice LP -> oxPool LP -> Staked (max)
     * @param solidPoolAddress The solid pool LP address to deposit and stake
     */
    function depositLpAndStake(address solidPoolAddress) external {
        // Fetch user proxy
        IUserProxy userProxy = createAndGetUserProxy();
        address userProxyOwnerAddress = userProxy.ownerAddress();

        // Fetch amount of Solid LP owned by owner
        uint256 amount = IERC20(solidPoolAddress).balanceOf(
            userProxyOwnerAddress
        );

        // Deposit and stake LP
        depositLpAndStake(solidPoolAddress, amount);
    }

    /**
     * @notice LP -> oxPool LP -> Staked
     * @param solidPoolAddress The solid pool LP address to deposit and stake
     * @param amount The amount of solid pool LP to deposit and stake
     */
    function depositLpAndStake(address solidPoolAddress, uint256 amount)
        public
    {
        // Fetch user proxy
        IUserProxy userProxy = createAndGetUserProxy();
        address userProxyOwnerAddress = userProxy.ownerAddress();

        // Receive LP from UserProxy owner
        IERC20(solidPoolAddress).transferFrom(
            userProxyOwnerAddress,
            address(this),
            amount
        );

        // Allow UserProxy to spend LP
        IERC20(solidPoolAddress).approve(address(userProxy), amount);

        // Deposit and stake LP via UserProxy
        userProxy.depositLpAndStake(solidPoolAddress, amount);
    }

    /**
     * @notice LP -> oxPool LP (max)
     * @param solidPoolAddress The solid pool LP address to deposit
     */
    function depositLp(address solidPoolAddress) external {
        // Fetch user proxy
        IUserProxy userProxy = createAndGetUserProxy();
        address userProxyOwnerAddress = userProxy.ownerAddress();

        // Fetch amount of Solid LP owned by owner
        uint256 amount = IERC20(solidPoolAddress).balanceOf(
            userProxyOwnerAddress
        );
        depositLp(solidPoolAddress, amount);
    }

    /**
     * @notice LP -> oxPool LP
     * @param solidPoolAddress The solid pool LP address to deposit
     * @param amount The amount of solid pool LP to deposit and stake
     */
    function depositLp(address solidPoolAddress, uint256 amount) public {
        // Fetch user proxy
        IUserProxy userProxy = createAndGetUserProxy();
        address userProxyOwnerAddress = userProxy.ownerAddress();

        // Receive LP from UserProxy owner
        IERC20(solidPoolAddress).transferFrom(
            userProxyOwnerAddress,
            address(this),
            amount
        );

        // Allow UserProxy to spend LP
        IERC20(solidPoolAddress).approve(address(userProxy), amount);

        // Deposit LP into oxPool via UserProxy
        userProxy.depositLp(solidPoolAddress, amount);
    }

    /**
     * @notice Staked oxPool LP -> oxPool LP -> LP (max)
     * @param solidPoolAddress The solid pool LP address to unstake and withdraw
     */
    function unstakeLpWithdrawAndClaim(address solidPoolAddress) external {
        // Fetch amount staked
        uint256 amount = _amountStaked(solidPoolAddress);

        // Withdraw and unstake
        unstakeLpWithdrawAndClaim(solidPoolAddress, amount);
    }

    /**
     * @notice Staked oxPool LP -> oxPool LP -> LP
     * @param solidPoolAddress The solid pool LP address to unstake and withdraw
     * @param amount The amount of solid pool LP to unstake and withdraw
     */
    function unstakeLpWithdrawAndClaim(address solidPoolAddress, uint256 amount)
        public
    {
        // Withdraw and unstake
        IUserProxy userProxy = createAndGetUserProxy();
        userProxy.unstakeLpAndWithdraw(solidPoolAddress, amount, true);
    }

    /**
     * @notice Staked oxPool LP -> oxPool LP -> LP (max)
     * @param solidPoolAddress The solid pool LP address to unstake and withdraw
     */
    function unstakeLpAndWithdraw(address solidPoolAddress) external {
        // Fetch amount staked
        uint256 amount = _amountStaked(solidPoolAddress);

        // Withdraw and unstake
        unstakeLpAndWithdraw(solidPoolAddress, amount);
    }

    /**
     * @notice Staked oxPool LP -> oxPool LP -> LP
     * @param solidPoolAddress The solid pool LP address to unstake and withdraw
     * @param amount The amount of solid pool LP to unstake and withdraw
     */
    function unstakeLpAndWithdraw(address solidPoolAddress, uint256 amount)
        public
    {
        // Withdraw and unstake
        IUserProxy userProxy = createAndGetUserProxy();
        userProxy.unstakeLpAndWithdraw(solidPoolAddress, amount, false);
    }

    function _amountStaked(address solidPoolAddress)
        internal
        returns (uint256)
    {
        // Fetch UserProxy
        IUserProxy userProxy = createAndGetUserProxy();

        // Determine amount currently staked
        address stakingAddress = oxLens.stakingRewardsBySolidPool(
            solidPoolAddress
        );
        uint256 amount = IERC20(stakingAddress).balanceOf(address(userProxy));
        return amount;
    }

    /**
     * @notice oxPool LP -> LP (max)
     * @param solidPoolAddress The solid pool LP address to withdraw
     */
    function withdrawLp(address solidPoolAddress) external {
        // Fetch user proxy
        IUserProxy userProxy = createAndGetUserProxy();
        address userProxyOwnerAddress = userProxy.ownerAddress();

        // Fetch amount of oxPool LP owned by UserProxy owner
        address oxPoolAddress = oxLens.oxPoolBySolidPool(solidPoolAddress);
        uint256 amount = IERC20(oxPoolAddress).balanceOf(userProxyOwnerAddress);
        withdrawLp(solidPoolAddress, amount);
    }

    /**
     * @notice oxPool LP -> LP
     * @param solidPoolAddress The solid pool LP address to withdraw
     * @param amount The amount of solid pool LP to withdraw
     */
    function withdrawLp(address solidPoolAddress, uint256 amount) public {
        // Fetch user proxy
        IUserProxy userProxy = createAndGetUserProxy();
        address userProxyOwnerAddress = userProxy.ownerAddress();

        // Receive oxPool LP from UserProxy owner
        address oxPoolAddress = oxLens.oxPoolBySolidPool(solidPoolAddress);
        IERC20(oxPoolAddress).transferFrom(
            userProxyOwnerAddress,
            address(this),
            amount
        );

        // Allow UserProxy to spend oxPool LP
        IERC20(oxPoolAddress).approve(address(userProxy), amount);

        // Withdraw oxPool LP via UserProxy (UserProxy will transfer it to owner)
        userProxy.withdrawLp(solidPoolAddress, amount);
    }

    /**
     * @notice oxPool LP -> Staked oxPool LP (max)
     * @param oxPoolAddress The oxPool LP address to stake
     */
    function stakeOxLp(address oxPoolAddress) public {
        // Fetch user proxy
        IUserProxy userProxy = createAndGetUserProxy();
        address userProxyOwnerAddress = userProxy.ownerAddress();

        // Fetch amount of oxPool LP owned by owner
        uint256 amount = IERC20(oxPoolAddress).balanceOf(userProxyOwnerAddress);
        stakeOxLp(oxPoolAddress, amount);
    }

    /**
     * @notice oxPool LP -> Staked oxPool LP
     * @param oxPoolAddress The oxPool LP address to stake
     * @param amount The amount of oxPool LP to stake
     */
    function stakeOxLp(address oxPoolAddress, uint256 amount) public {
        // Fetch user proxy
        IUserProxy userProxy = createAndGetUserProxy();
        address userProxyOwnerAddress = userProxy.ownerAddress();

        // Receive oxPool LP from owner
        IERC20(oxPoolAddress).transferFrom(
            userProxyOwnerAddress,
            address(this),
            amount
        );

        // Allow UserProxy to spend oxPool LP
        IERC20(oxPoolAddress).approve(address(userProxy), amount);

        // Stake oxPool LP
        userProxy.stakeOxLp(oxPoolAddress, amount);
    }

    /**
     * @notice Staked oxPool LP -> oxPool LP (max)
     * @param oxPoolAddress The oxPool LP address to unstake
     */
    function unstakeOxLp(address oxPoolAddress) public {
        // Fetch UserProxy
        IUserProxy userProxy = createAndGetUserProxy();

        // Fetch amount of oxPool LP currently staked
        address stakingAddress = oxLens.stakingRewardsByOxPool(oxPoolAddress);
        uint256 amount = IERC20(stakingAddress).balanceOf(address(userProxy));

        // Unstake
        unstakeOxLp(oxPoolAddress, amount);
    }

    /**
     * @notice Staked oxPool LP -> oxPool LP
     * @param oxPoolAddress The oxPool LP address to unstake
     * @param amount The amount of oxPool LP to unstake
     */
    function unstakeOxLp(address oxPoolAddress, uint256 amount) public {
        // Fetch UserProxy
        IUserProxy userProxy = createAndGetUserProxy();

        // Unstake
        userProxy.unstakeOxLp(oxPoolAddress, amount);
    }

    /**
     * @notice Claim staking rewards given a staking pool address
     * @param stakingPoolAddress Address of MultiRewards contract
     */
    function claimStakingRewards(address stakingPoolAddress) public {
        // Fetch UserProxy
        IUserProxy userProxy = createAndGetUserProxy();

        // Unstake
        userProxy.claimStakingRewards(stakingPoolAddress);
    }

    /**
     * @notice Claim all staking rewards
     */
    function claimStakingRewards() public {
        // Fetch UserProxy
        IUserProxy userProxy = createAndGetUserProxy();

        // Unstake
        userProxy.claimStakingRewards();
    }

    /*******************************************************
     *                 SOLID and veNFT interactions
     *******************************************************/

    /**
     * @notice SOLID -> veNFT -> oxSOLID (max)
     */
    function convertSolidToOxSolid() external {
        // Fetch user proxy
        IUserProxy userProxy = createAndGetUserProxy();
        address userProxyOwnerAddress = userProxy.ownerAddress();

        // Fetch amount of SOLID owned by owner
        uint256 amount = solid.balanceOf(userProxyOwnerAddress);
        convertSolidToOxSolid(amount);
    }

    /**
     * @notice SOLID -> veNFT -> oxSOLID
     * @param amount The amount of SOLID to convert
     */
    function convertSolidToOxSolid(uint256 amount) public {
        // Fetch user proxy
        IUserProxy userProxy = createAndGetUserProxy();
        address userProxyOwnerAddress = userProxy.ownerAddress();

        // Transfer SOLID to this contract
        solid.transferFrom(userProxyOwnerAddress, address(this), amount);

        // Allow UserProxy to spend SOLID
        solid.approve(address(userProxy), amount);

        // Convert SOLID to oxSOLID
        userProxy.convertSolidToOxSolid(amount);
    }

    /**
     * @notice SOLID -> veNFT -> oxSOLID -> Staked oxSOLID (max)
     */
    function convertSolidToOxSolidAndStake() external {
        // Fetch user proxy
        IUserProxy userProxy = createAndGetUserProxy();
        address userProxyOwnerAddress = userProxy.ownerAddress();

        // Fetch amount of SOLID owner by UserProxy owner
        uint256 amount = solid.balanceOf(userProxyOwnerAddress);

        // Convert SOLID to oxSOLID and stake
        convertSolidToOxSolidAndStake(amount);
    }

    /**
     * @notice SOLID -> veNFT -> oxSOLID -> Staked oxSOLID
     * @param amount The amount of SOLID to convert
     */
    function convertSolidToOxSolidAndStake(uint256 amount) public {
        // Fetch user proxy
        IUserProxy userProxy = createAndGetUserProxy();
        address userProxyOwnerAddress = userProxy.ownerAddress();

        // Transfer SOLID to this contract
        solid.transferFrom(userProxyOwnerAddress, address(this), amount);

        // Allow UserProxy to spend SOLID
        solid.approve(address(userProxy), amount);

        // Convert SOLID to oxSOLID
        userProxy.convertSolidToOxSolidAndStake(amount);
    }

    /**
     * @notice veNFT -> oxSOLID
     * @param tokenId The tokenId of the NFT to convert
     */
    function convertNftToOxSolid(uint256 tokenId) public {
        // Fetch UserProxy
        IUserProxy userProxy = createAndGetUserProxy();
        address userProxyOwnerAddress = userProxy.ownerAddress();

        // Transfer NFT to this contract
        ve.safeTransferFrom(userProxyOwnerAddress, address(this), tokenId);

        // Transfer NFT to user proxy to convert
        ve.approve(address(userProxy), tokenId);
        userProxy.convertNftToOxSolid(tokenId);
    }

    /**
     * @notice veNFT -> oxSOLID -> Staked oxSOLID
     * @param tokenId The tokenId of the NFT to convert
     */
    function convertNftToOxSolidAndStake(uint256 tokenId) external {
        // Fetch user proxy
        IUserProxy userProxy = createAndGetUserProxy();
        address userProxyOwnerAddress = userProxy.ownerAddress();

        // Transfer NFT to this contract
        ve.safeTransferFrom(userProxyOwnerAddress, address(this), tokenId);

        // Convert SOLID to oxSOLID and stake
        ve.approve(address(userProxy), tokenId);
        userProxy.convertNftToOxSolidAndStake(tokenId);
    }

    /**
     * @notice oxSOLID -> Staked oxSOLID (max)
     */
    function stakeOxSolid() external {
        // Fetch amount of oxSOLID currently staked
        uint256 amount = oxSolid.balanceOf(msg.sender);

        // Stake oxSOLID
        stakeOxSolid(amount);
    }

    /**
     * @notice oxSOLID -> Staked oxSOLID
     * @param amount The amount of oxSOLID to stake
     */
    function stakeOxSolid(uint256 amount) public {
        // Fetch user proxy
        IUserProxy userProxy = createAndGetUserProxy();
        address userProxyOwnerAddress = userProxy.ownerAddress();

        // Receive oxSOLID from owner
        oxSolid.transferFrom(userProxyOwnerAddress, address(this), amount);

        // Allow UserProxy to spend oxSOLID
        oxSolid.approve(address(userProxy), amount);

        // Stake oxSOLID via UserProxy
        userProxy.stakeOxSolid(amount);
    }

    /**
     * @notice oxSOLID -> Staked oxSOLID in oxdV1Rewards after burning OXDv1 (max)
     */
    function stakeOxSolidInOxdV1() external {
        // Fetch amount of oxSOLID currently staked
        uint256 amount = oxSolid.balanceOf(msg.sender);

        // Stake oxSOLID
        stakeOxSolidInOxdV1(amount);
    }

    /**
     * @notice oxSOLID -> Staked oxSOLID in oxdV1Rewards after burning OXDv1
     * @param amount The amount of oxSOLID to stake
     */
    function stakeOxSolidInOxdV1(uint256 amount) public {
        // Fetch user proxy
        IUserProxy userProxy = createAndGetUserProxy();
        address userProxyOwnerAddress = userProxy.ownerAddress();

        // Receive oxSOLID from owner
        oxSolid.transferFrom(userProxyOwnerAddress, address(this), amount);

        // Allow UserProxy to spend oxSOLID
        oxSolid.approve(address(userProxy), amount);

        // Stake oxSOLID via UserProxy
        userProxy.stakeOxSolidInOxdV1(amount);
    }

    /**
     * @notice Staked oxSOLID -> oxSOLID (max)
     */
    function unstakeOxSolid() external {
        // Fetch UserProxy
        IUserProxy userProxy = createAndGetUserProxy();

        // Fetch amount of oxSOLID currently staked
        uint256 amount = oxLens.stakedOxSolidBalanceOf(msg.sender);

        // Unstake oxSOLID
        userProxy.unstakeOxSolid(amount);
    }

    /**
     * @notice Staked oxSOLID -> oxSOLID
     * @param amount The amount of oxSOLID to unstake
     */
    function unstakeOxSolid(uint256 amount) public {
        // Fetch UserProxy
        IUserProxy userProxy = createAndGetUserProxy();
        address stakingAddress = oxLens.oxSolidRewardsPoolAddress();

        // Unstake via UserProxy
        userProxy.unstakeOxSolid(amount);
    }

    /**
     * @notice Staked oxSOLID in oxdV1Rewards -> oxSOLID
     * @param amount The amount of oxSOLID to unstake
     */
    function unstakeOxSolidInOxdV1(uint256 amount) public {
        // Fetch UserProxy
        IUserProxy userProxy = createAndGetUserProxy();
        address stakingAddress = oxLens.oxdV1RewardsAddress();

        // Unstake via UserProxy
        userProxy.unstakeOxSolid(stakingAddress, amount);
    }

    /**
     * @notice Generalized Staked oxSOLID -> oxSOLID
     * @param stakingAddress The MultiRewards Address to unstake from
     * @param amount The amount of oxSOLID to unstake
     */
    function unstakeOxSolid(address stakingAddress, uint256 amount) public {
        // Fetch UserProxy
        IUserProxy userProxy = createAndGetUserProxy();

        // Unstake via UserProxy
        userProxy.unstakeOxSolid(stakingAddress, amount);
    }

    /**
     * @notice Claim staking rewards for staking oxSOLID
     */
    function claimOxSolidStakingRewards() public {
        // Fetch UserProxy
        IUserProxy userProxy = createAndGetUserProxy();
        address stakingAddress;
        if (oxLens.isPartner(address(userProxy))) {
            stakingAddress = oxLens.partnersRewardsPoolAddress();
        } else {
            stakingAddress = oxLens.oxSolidRewardsPoolAddress();
        }

        // Claim rewards
        userProxy.claimStakingRewards(stakingAddress);
    }

    /*******************************************************
     *                   OXDv1 Redemption
     *******************************************************/

    /**
     * @notice OXDv1 -> oxSOLID (max)
     */
    function redeemOxdV1() public {
        // Fetch amount
        uint256 amount = IERC20(oxLens.oxdV1Address()).balanceOf(msg.sender);

        // Unstake via UserProxy
        redeemOxdV1(amount);
    }

    /**
     * @notice OXDv1 -> oxSOLID
     * @param amount The amount of OXDv1 to redeem
     */
    function redeemOxdV1(uint256 amount) public {
        // Fetch UserProxy
        IUserProxy userProxy = createAndGetUserProxy();
        address userProxyOwnerAddress = userProxy.ownerAddress();

        // Receive OXD v1 from owner
        IERC20(oxLens.oxdV1Address()).transferFrom(
            userProxyOwnerAddress,
            address(this),
            amount
        );

        // Allow UserProxy to spend OXD v1
        IERC20(oxLens.oxdV1Address()).approve(address(userProxy), amount);

        // Unstake via UserProxy
        userProxy.redeemOxdV1(amount);
    }

    /**
     * @notice OXDv1 -> oxSOLID staked in oxdV1Rewards (max)
     */
    function redeemAndStakeOxdV1() public {
        // Fetch amount
        uint256 amount = IERC20(oxLens.oxdV1Address()).balanceOf(msg.sender);

        // Unstake via UserProxy
        redeemAndStakeOxdV1(amount);
    }

    /**
     * @notice OXDv1 -> oxSOLID staked in oxdV1Rewards
     * @param amount The amount of OXDv1 to redeem
     */
    function redeemAndStakeOxdV1(uint256 amount) public {
        // Fetch UserProxy
        IUserProxy userProxy = createAndGetUserProxy();
        address userProxyOwnerAddress = userProxy.ownerAddress();

        // Receive OXD v1 from owner
        IERC20(oxLens.oxdV1Address()).transferFrom(
            userProxyOwnerAddress,
            address(this),
            amount
        );

        // Allow UserProxy to spend OXD v1
        IERC20(oxLens.oxdV1Address()).approve(address(userProxy), amount);

        // Unstake via UserProxy
        userProxy.redeemAndStakeOxdV1(amount);
    }

    /**
     * @notice Claim OXDv1 oxSOLID staking rewards
     */
    function claimV1OxSolidStakingRewards() public {
        // Fetch UserProxy
        IUserProxy userProxy = createAndGetUserProxy();

        // Claim rewards
        userProxy.claimStakingRewards(oxLens.oxdV1RewardsAddress());
    }

    /*******************************************************
     *                   Partner migration
     *******************************************************/

    /**
     * @notice Migrates nonparters who recently got whitelisted as partners
     */
    function migrateOxSolidToPartner() external {
        IUserProxy userProxy = createAndGetUserProxy();
        userProxy.migrateOxSolidToPartner();
    }

    /*******************************************************
     *                        vlOXD
     *******************************************************/

    /**
     * @notice Vote lock OXD for 16 weeks (non-transferrable)
     * @param amount Amount of OXD to lock
     * @param spendRatio Spend ratio for OxdLocker
     * @dev OxdLocker utilizes the same code as CvxLocker
     */
    function voteLockOxd(uint256 amount, uint256 spendRatio) external {
        // Fetch UserProxy
        IUserProxy userProxy = createAndGetUserProxy();
        address userProxyOwnerAddress = userProxy.ownerAddress();

        // Receive OXD from user
        oxd.transferFrom(userProxyOwnerAddress, address(this), amount);

        // Allow UserProxy to spend OXD
        oxd.approve(address(userProxy), amount);

        // Lock OXD via UserProxy
        userProxy.voteLockOxd(amount, spendRatio);
    }

    /**
     * @notice Withdraw vote locked OXD
     * @param spendRatio Spend ratio
     */
    function withdrawVoteLockedOxd(uint256 spendRatio) external {
        // Fetch UserProxy
        IUserProxy userProxy = createAndGetUserProxy();

        // Withdraw vote locked OXD and claim
        userProxy.withdrawVoteLockedOxd(spendRatio, false);
    }

    /**
     * @notice Relock vote locked OXD
     * @param spendRatio Spend ratio
     */
    function relockVoteLockedOxd(uint256 spendRatio) external {
        // Fetch UserProxy
        IUserProxy userProxy = createAndGetUserProxy();

        // Withdraw vote locked OXD and claim
        userProxy.relockVoteLockedOxd(spendRatio);
    }

    /**
     * @notice Claim vlOXD staking rewards
     */
    function claimVlOxdStakingRewards() public {
        // Fetch UserProxy
        IUserProxy userProxy = createAndGetUserProxy();

        // Claim rewards
        userProxy.claimVlOxdRewards();
    }

    /*******************************************************
     *                       Voting
     *******************************************************/

    /**
     * @notice Vote for a pool given a pool address and weight
     * @param poolAddress The pool adress to vote for
     * @param weight The new vote weight (can be positive or negative)
     */
    function vote(address poolAddress, int256 weight) external {
        // Fetch UserProxy
        IUserProxy userProxy = createAndGetUserProxy();

        // Withdraw vote locked OXD and claim
        userProxy.vote(poolAddress, weight);
    }

    /**
     * @notice Batch vote
     * @param votes Votes
     */
    function vote(IUserProxy.Vote[] memory votes) external {
        // Fetch UserProxy
        IUserProxy userProxy = createAndGetUserProxy();

        // Clear vote delegate
        userProxy.vote(votes);
    }

    /**
     * @notice Remove a user's vote given a pool address
     * @param poolAddress The address of the pool whose vote will be deleted
     */
    function removeVote(address poolAddress) public {
        // Fetch UserProxy
        IUserProxy userProxy = createAndGetUserProxy();

        // Withdraw vote locked OXD and claim
        userProxy.removeVote(poolAddress);
    }

    /**
     * @notice Delete all vote for a user
     */
    function resetVotes() external {
        // Fetch UserProxy
        IUserProxy userProxy = createAndGetUserProxy();

        // Withdraw vote locked OXD and claim
        userProxy.resetVotes();
    }

    /**
     * @notice Set vote delegate for an account
     * @param accountAddress New delegate address
     */
    function setVoteDelegate(address accountAddress) external {
        // Fetch UserProxy
        IUserProxy userProxy = createAndGetUserProxy();

        // Set vote delegate
        userProxy.setVoteDelegate(accountAddress);
    }

    /**
     * @notice Clear vote delegate for an account
     */
    function clearVoteDelegate() external {
        // Fetch UserProxy
        IUserProxy userProxy = createAndGetUserProxy();

        // Clear vote delegate
        userProxy.clearVoteDelegate();
    }

    /*******************************************************
     *                   Helper Utilities
     *******************************************************/

    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    // Only allow users to interact with their proxy
    function createAndGetUserProxy() internal returns (IUserProxy) {
        return
            IUserProxy(
                IUserProxyFactory(userProxyFactoryAddress)
                    .createAndGetUserProxy(msg.sender)
            );
    }

    function claimAllStakingRewards() public {
        claimStakingRewards();
        claimOxSolidStakingRewards();
        claimV1OxSolidStakingRewards();
        claimVlOxdStakingRewards();
    }
}
