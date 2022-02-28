// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;
import "./UserProxyStorageLayout.sol";

/**
 * @title UserProxyVotingInteractions
 * @author 0xDAO
 * @notice Core logic for all user voting interactions
 * @dev All implementations must inherit from UserProxyStorageLayout
 */
contract UserProxyVotingInteractions is UserProxyStorageLayout {
    /*******************************************************
     *                   vlOXD and voting
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
            userProxy.claimStakingRewards(vlOxdAddress);
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

    /**
     * @notice Vote for a pool given a pool address and weight
     * @param poolAddress The pool adress to vote for
     * @param weight The new vote weight (can be positive or negative)
     */
    function vote(address poolAddress, int256 weight)
        external
        onlyUserProxyInterfaceOrOwner
    {
        oxLens.votingSnapshot().vote(poolAddress, weight);
    }

    /**
     * @notice Batch vote
     * @param votes Votes
     */
    function vote(IVotingSnapshot.Vote[] memory votes)
        external
        onlyUserProxyInterfaceOrOwner
    {
        oxLens.votingSnapshot().vote(votes);
    }

    /**
     * @notice Remove a user's vote given a pool address
     * @param poolAddress The address of the pool whose vote will be deleted
     */
    function removeVote(address poolAddress)
        public
        onlyUserProxyInterfaceOrOwner
    {
        oxLens.votingSnapshot().removeVote(poolAddress);
    }

    /**
     * @notice Delete all vote for a user
     */
    function resetVotes() external onlyUserProxyInterfaceOrOwner {
        oxLens.votingSnapshot().resetVotes();
    }

    /**
     * @notice Set vote delegate for an account
     * @param accountAddress New delegate address
     */
    function setVoteDelegate(address accountAddress)
        external
        onlyUserProxyInterfaceOrOwner
    {
        oxLens.votingSnapshot().setVoteDelegate(accountAddress);
    }

    /**
     * @notice Clear vote delegate for an account
     */
    function clearVoteDelegate() external onlyUserProxyInterfaceOrOwner {
        oxLens.votingSnapshot().clearVoteDelegate();
    }
}
