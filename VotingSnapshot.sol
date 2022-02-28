// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;
import "./interfaces/IVe.sol";
import "./interfaces/IVoterProxy.sol";
import "./interfaces/IVotingSnapshot.sol";
import "./interfaces/IVlOxd.sol";
import "./libraries/BinarySearch.sol";
import "./libraries/Math.sol";
import "./Governable.sol";
import "./ProxyImplementation.sol";

/**
 * @author 0xDAO
 * @title On-chain voting snapshot for SOLID emissions
 * @dev Rules:
 *        - Users vote using their vote locked OXD (vlOXD) balance
 *        - Users can vote and change their votes at any time
 *        - Users can vote for up to `maxVotesPerAccount` pools
 *        - Users do not need to vote every week for their votes to count
 *        - Votes can be positive or negative
 *        - Positive and negative votes of the same value have the same weight in the context of a user
 *        - Voting snapshots are submitted directly before the period epoch (Thursday 00:00+00 UTC)
 *        - Only the top voted `maxPoolsLength` pools will be voted on every week (this is due to a max vote count per NFT in Solidly)
 *        - Bribes and fee voting are handled separately
 */
contract VotingSnapshot is IVotingSnapshot, Governable, ProxyImplementation {
    /*******************************************************
     *                     Configuration
     *******************************************************/

    // Set up binary search tree
    using BinarySearch for BinarySearch.Tree;
    BinarySearch.Tree tree;

    // Constants
    uint256 internal tokenId;
    uint256 internal constant week = 86400 * 7;
    uint256 internal constant hour = 3600;

    // Options
    uint256 public window = hour * 4;
    uint256 public maxPoolsLength = 10;
    uint256 public maxVotesPerAccount = 10;

    // Important addresses
    address public vlOxdAddress;
    address public veAddress;
    address public voterProxyAddress;

    // Global vote tracking
    mapping(uint256 => uint256) public votesLengthByWeight;
    mapping(uint256 => mapping(uint256 => Vote)) public votesByWeight;
    mapping(address => uint256) public weightByPoolUnsigned;
    mapping(address => int256) public weightByPoolSigned;
    mapping(address => uint256) public voteIndexByPool;
    uint256 public uniqueVotesLength;
    uint256 public votesLength;

    // User vote tracking
    mapping(address => uint256) public voteWeightUsedByAccount;
    mapping(address => uint256) public votesLengthByAccount;
    mapping(address => mapping(address => Vote)) public accountVoteByPool;
    mapping(address => mapping(uint256 => Vote)) public accountVoteByIndex;
    mapping(address => mapping(address => uint256))
        public accountVoteIndexByPool;

    // Vote delegation
    mapping(address => address) public voteDelegateByAccount;

    // Internal helpers
    IVlOxd internal vlOxd;
    IVe internal ve;
    IVoterProxy internal voterProxy;

    // Modifiers
    modifier onlyVoteDelegateOrOwner(address accountAddress) {
        bool voteDelegateSet = voteDelegateByAccount[accountAddress] !=
            address(0);
        if (voteDelegateSet) {
            if (accountAddress == msg.sender) {
                revert(
                    "You have delegated your voting power (you cannot vote)"
                );
            }
            require(
                voteDelegateByAccount[accountAddress] == msg.sender,
                "Only vote delegate can vote"
            );
        } else {
            require(
                accountAddress == msg.sender,
                "Only users and delegates can vote"
            );
        }
        _;
    }

    /**
     * @notice Initialize proxy storage
     */
    function initializeProxyStorage(
        address _vlOxdAddress,
        address _veAddress,
        address _voterProxyAddress
    ) public checkProxyInitialized {
        // From Governable
        governanceAddress = msg.sender;

        vlOxdAddress = _vlOxdAddress;
        veAddress = _veAddress;
        voterProxyAddress = _voterProxyAddress;
        vlOxd = IVlOxd(vlOxdAddress);
        ve = IVe(_veAddress);
        voterProxy = IVoterProxy(voterProxyAddress);
        tokenId = voterProxy.primaryTokenId();
    }

    /*******************************************************
     *                 Pool vote registration
     *******************************************************/

    /**
     * @notice Register a pool vote in our binary search tree given a vote
     * @param vote The new vote to register (includes pool address and vote weight delta)
     * @dev We utilize a binary search tree to allow votes to be sorted with O(log n) efficiency
     * @dev Pool votes can be positive or negative
     * @dev This method is only called by the user `vote(Vote)` method
     */
    function registerVote(Vote memory vote) internal {
        // Find current weight for pool
        address poolAddress = vote.poolAddress;
        int256 currentPoolWeight = weightByPoolSigned[poolAddress];

        // Find new weight for pool based on new weight delta
        int256 newPoolWeight = currentPoolWeight + vote.weight;

        // Fetch absolute pool weights
        uint256 newPoolWeightAbsolute = Math.abs(newPoolWeight);
        uint256 currentPoolWeightAbsolute = Math.abs(currentPoolWeight);

        // Fetch number of votes per weight
        uint256 newVotesLengthPerWeight = votesLengthByWeight[
            newPoolWeightAbsolute
        ];
        uint256 currentVotesLengthPerWeight = votesLengthByWeight[
            currentPoolWeightAbsolute
        ];

        // If pool has no votes
        bool poolHasNoVotes = currentPoolWeight == 0;
        if (poolHasNoVotes) {
            // Check to see if weight exists in tree
            bool newWeightExists = weightExists(newPoolWeightAbsolute);

            // If new pool weight exists
            if (newWeightExists) {
                // Append vote to weight list
                votesByWeight[newPoolWeightAbsolute][
                    newVotesLengthPerWeight
                ] = vote;
                voteIndexByPool[poolAddress] = newVotesLengthPerWeight;
            } else {
                // Otherwise, create a new weight node and append the current vote
                insertWeight(newPoolWeightAbsolute);
                votesByWeight[newPoolWeightAbsolute][0] = vote;
                voteIndexByPool[poolAddress] = 0;
                uniqueVotesLength++;
            }

            // Increase total number of votes
            votesLength++;

            // Increase number of votes for this specific weight
            votesLengthByWeight[newPoolWeightAbsolute]++;

            // Set signed and unsigned weights for this pool
            weightByPoolUnsigned[vote.poolAddress] = Math.abs(vote.weight);
            weightByPoolSigned[vote.poolAddress] = vote.weight;
        } else {
            /**
             * Pool already has a vote, so we need to find and update the existing vote.
             * Iterate through votes for the current weight list to find the vote we need to update.
             */
            for (
                uint256 voteIndex;
                voteIndex < currentVotesLengthPerWeight;
                voteIndex++
            ) {
                Vote memory currentVote = votesByWeight[
                    currentPoolWeightAbsolute
                ][voteIndex];

                // Once we find the vote, update it
                if (currentVote.poolAddress == poolAddress) {
                    /**
                     * If vote has changed, remove the vote and add it again with the new weight.
                     * First delete the existing vote.
                     */
                    unregisterVote(vote, voteIndex);

                    // If the new vote weight is not zero re-register the pool vote using the updated weight
                    bool newVoteIsNotZero = newPoolWeight != 0;
                    if (newVoteIsNotZero) {
                        Vote memory updatedVote = Vote({
                            poolAddress: poolAddress,
                            weight: newPoolWeight
                        });
                        registerVote(updatedVote);
                    }
                    return;
                }
            }
        }
    }

    /**
     * @notice Unregister/delete a vote
     * @param vote The vote object to unregister (includes pool address and vote weight delta)
     * @param voteIndex The position of the vote in the current weight node
     * @dev This is only called by `registerVote(Vote)` when updating votes
     */
    function unregisterVote(Vote memory vote, uint256 voteIndex) internal {
        // Make sure node exists
        address poolAddress = vote.poolAddress;
        uint256 currentPoolWeightAbsolute = weightByPoolUnsigned[poolAddress];
        bool weightExists = weightExists(currentPoolWeightAbsolute);
        require(weightExists, "Weight node does not exist");

        // Find current weight node length
        uint256 votesLengthPerWeight = votesLengthByWeight[
            currentPoolWeightAbsolute
        ];

        // If there is only one item in the weight node, remove the node
        if (votesLengthPerWeight == 1) {
            removeWeight(currentPoolWeightAbsolute);
            uniqueVotesLength--;
        }

        // Find the index of the vote to remove in the weight node
        uint256 indexOfVoteInWeightList = voteIndexByPool[poolAddress];

        // Store the last vote of the weight node
        Vote memory lastVote = votesByWeight[currentPoolWeightAbsolute][
            votesLengthPerWeight - 1
        ];

        // Replace the vote to remove with the last vote
        votesByWeight[currentPoolWeightAbsolute][
            indexOfVoteInWeightList
        ] = lastVote;

        // Decrement votes length
        votesLength--;
        votesLengthByWeight[currentPoolWeightAbsolute]--;

        // Delete pool weight associations
        delete weightByPoolUnsigned[poolAddress];
        delete weightByPoolSigned[poolAddress];
        delete voteIndexByPool[poolAddress];
    }

    /**
     * @notice Determine current active period for voting epoch
     */
    function nextEpoch() public view returns (uint256) {
        return ((block.timestamp + week) / week) * week;
    }

    /**
     * @notice Determine the next time a vote can be submitted
     */
    function nextVoteSubmission() public view returns (uint256) {
        return nextEpoch() - window;
    }

    /*******************************************************
     *                  User vote tracking
     *******************************************************/

    /**
     * @notice Find the maximum voting power available for an account
     * @param accountAddress The address to check
     */
    function voteWeightTotalByAccount(address accountAddress)
        public
        view
        returns (uint256)
    {
        return vlOxd.lockedBalanceOf(accountAddress);
    }

    function voteWeightAvailableByAccount(address accountAddress)
        public
        view
        returns (uint256)
    {
        return
            voteWeightTotalByAccount(accountAddress) -
            voteWeightUsedByAccount[accountAddress];
    }

    /*******************************************************
     *                      User voting
     *******************************************************/

    /**
     * @notice Vote for a pool given a pool address and weight
     * @param poolAddress The pool adress to vote for
     * @param weight The new vote weight (can be positive or negative)
     */
    function vote(address poolAddress, int256 weight) public {
        address accountAddress = msg.sender;
        vote(accountAddress, poolAddress, weight);
    }

    /**
     * @notice Vote for a pool on behalf of a user given a pool address and weight
     * @param poolAddress The pool adress to vote for
     * @param weight The new vote weight (can be positive or negative)
     */
    function vote(
        address accountAddress,
        address poolAddress,
        int256 weight
    ) public onlyVoteDelegateOrOwner(accountAddress) {
        // Fetch user's vlOxd balance and use this as maximum user weight
        uint256 maximumUserWeight = voteWeightTotalByAccount(accountAddress);

        // Initialize vote delta variable
        int256 accountVoteDelta;

        // Find old and new votes
        Vote memory oldVote = accountVoteByPool[accountAddress][poolAddress];
        Vote memory newVote = Vote({poolAddress: poolAddress, weight: weight});

        // Determine whether or not user has voted for this pool yet
        bool accountHasntVotedForPool = oldVote.poolAddress == address(0);

        // If the user has not voted for the pool
        if (accountHasntVotedForPool) {
            // Do nothing if vote weight is zero
            if (weight == 0) {
                return;
            }

            // Add vote the user's vote list
            uint256 votesLength = votesLengthByAccount[accountAddress];
            accountVoteByIndex[accountAddress][votesLength] = newVote;
            accountVoteIndexByPool[accountAddress][poolAddress] = votesLength;
            votesLengthByAccount[accountAddress]++;

            // Store new vote delta
            accountVoteDelta = newVote.weight;

            // Make sure the user has not exceeded their maximum number of votes
            require(
                votesLengthByAccount[accountAddress] <= maxVotesPerAccount,
                "User has exceeded maximum number of votes allowed"
            );

            // Increase used vote weight for account
            voteWeightUsedByAccount[accountAddress] += Math.abs(newVote.weight);
        } else {
            /**
             * The user has already voted for this pool. Update the vote
             */

            // If the new vote weight is zero delete vote
            if (weight == 0) {
                return removeVote(accountAddress, poolAddress);
            }

            // Find the user's vote index and update it
            uint256 voteIndex = accountVoteIndexByPool[accountAddress][
                poolAddress
            ];
            accountVoteByIndex[accountAddress][voteIndex] = newVote;

            // Adjust user's vote weight
            uint256 currentWeightUsed = voteWeightUsedByAccount[accountAddress];
            voteWeightUsedByAccount[accountAddress] =
                currentWeightUsed -
                Math.abs(oldVote.weight) +
                Math.abs(newVote.weight);

            // Calculate vote delta
            accountVoteDelta = newVote.weight - oldVote.weight;
        }

        // Save the new vote
        accountVoteByPool[accountAddress][poolAddress] = newVote;

        // Make sure user has not exceeded their voting capacity
        require(
            voteWeightUsedByAccount[accountAddress] <= maximumUserWeight,
            "Exceeded user voting capacity"
        );

        // Globally register the vote
        registerVote(
            Vote({poolAddress: poolAddress, weight: accountVoteDelta})
        );
    }

    /**
     * @notice Batch voting
     * @param votes Votes
     */
    function vote(Vote[] memory votes) external {
        for (uint256 voteIndex; voteIndex < votes.length; voteIndex++) {
            Vote memory _vote = votes[voteIndex];
            vote(_vote.poolAddress, _vote.weight);
        }
    }

    /**
     * @notice Batch voting
     * @param votes Votes
     */
    function vote(address accountAddress, Vote[] memory votes) external {
        for (uint256 voteIndex; voteIndex < votes.length; voteIndex++) {
            Vote memory _vote = votes[voteIndex];
            vote(accountAddress, _vote.poolAddress, _vote.weight);
        }
    }

    /**
     * @notice Remove a user's vote given a pool address
     * @param poolAddress The address of the pool whose vote will be deleted
     */
    function removeVote(address poolAddress) public {
        address accountAddress = msg.sender;
        removeVote(accountAddress, poolAddress);
    }

    /**
     * @notice Remove a user's vote given a pool address
     * @param poolAddress The address of the pool whose vote will be deleted
     */
    function removeVote(address accountAddress, address poolAddress)
        public
        onlyVoteDelegateOrOwner(accountAddress)
    {
        // Find vote to remove
        Vote memory voteToRemove = accountVoteByPool[accountAddress][
            poolAddress
        ];

        // If user hasn't voted for this pool do nothing (there is nothing to remove)
        bool accountHasntVotedForPool = voteToRemove.poolAddress == address(0);
        if (accountHasntVotedForPool) {
            return;
        }

        // Find the user's last vote
        uint256 votesLength = votesLengthByAccount[accountAddress];
        Vote memory lastVote = accountVoteByIndex[accountAddress][
            votesLength - 1
        ];

        // Find the user's vote index and replace it with the last vote
        uint256 voteIndex = accountVoteIndexByPool[accountAddress][poolAddress];
        accountVoteByIndex[accountAddress][voteIndex] = lastVote;

        // Reduce votes length
        votesLengthByAccount[accountAddress]--;

        // Remove vote weight used by account
        voteWeightUsedByAccount[accountAddress] -= Math.abs(
            voteToRemove.weight
        );

        // Remove account vote by pool
        delete accountVoteByPool[accountAddress][poolAddress];

        // Register a negating vote for the user
        registerVote(
            Vote({poolAddress: poolAddress, weight: -voteToRemove.weight})
        );
    }

    /**
     * @notice Delete all vote for a user
     */
    function resetVotes() public {
        address accountAddress = msg.sender;
        resetVotes(accountAddress);
    }

    /**
     * @notice Delete all vote for a user
     * @param accountAddress The address for which to remove votes
     */
    function resetVotes(address accountAddress) public {
        Vote[] memory _votes = votesByAccount(accountAddress);
        for (uint256 voteIndex; voteIndex < _votes.length; voteIndex++) {
            Vote memory vote = _votes[voteIndex];
            removeVote(accountAddress, vote.poolAddress);
        }
    }

    /*******************************************************
     *                    Vote submitting
     *******************************************************/

    /**
     * @notice Prepare Solidly vote
     * @return Returns a list of pool addresses and votes
     */
    function prepareVote()
        public
        view
        returns (address[] memory, int256[] memory)
    {
        // Fetch top votes and total weight
        Vote[] memory _topVotes = topVotes();
        uint256 _topVotesWeight = topVotesWeight();

        // Fetch balance of NFT to vote with
        uint256 veBalanceOfNft = totalVoteWeight();

        // Construct vote
        address[] memory poolsAddresses = new address[](_topVotes.length);
        int256[] memory _votes = new int256[](_topVotes.length);
        for (uint256 voteIndex; voteIndex < _topVotes.length; voteIndex++) {
            // Set pool addresses
            Vote memory vote = _topVotes[voteIndex];
            poolsAddresses[voteIndex] = vote.poolAddress;

            // Set pool votes
            uint256 absoluteWeight = (veBalanceOfNft * Math.abs(vote.weight)) /
                _topVotesWeight;
            _votes[voteIndex] = int256(absoluteWeight);
        }
        return (poolsAddresses, _votes);
    }

    /**
     * @notice Submit vote to Solidly
     */
    function submitVote() external {
        (
            address[] memory poolsAddresses,
            int256[] memory votes
        ) = prepareVote();
        voterProxy.vote(poolsAddresses, votes);
        require(
            block.timestamp >= nextVoteSubmission() &&
                block.timestamp < nextEpoch(),
            "Votes can only be submitted within the allowed timeframe window"
        );
    }

    /*******************************************************
     *                     View methods
     *******************************************************/

    /**
     * @notice Fetch a sorted list of all votes (may run out of gas, if so use pagination)
     * @return Returns a list of sorted votes
     */
    function votes() external view returns (Vote[] memory) {
        return votes(votesLength);
    }

    /**
     * @notice Fetch a sorted list of votes
     * @param length The number of votes to fetch
     * @return Returns  a list of sorted votes
     */
    function votes(uint256 length) public view returns (Vote[] memory) {
        // Find current highest vote
        uint256 currentWeight = highestWeight();

        // Calculate number of votes to return
        uint256 votesToReturnLength = Math.min(votesLength, length);

        // Create new votes object
        Vote[] memory _votes = new Vote[](votesToReturnLength);

        // Use currentIndex to flatten the list of votes
        uint256 currentIndex;

        // Iterate over weight nodes
        for (
            uint256 weightIndex;
            weightIndex < uniqueVotesLength;
            weightIndex++
        ) {
            // For every vote in the weight node
            uint256 votesLengthForWeight = votesLengthByWeight[currentWeight];
            for (
                uint256 voteIndex;
                voteIndex < votesLengthForWeight;
                voteIndex++
            ) {
                // Add the vote to the votes list and increase currentIndex
                _votes[currentIndex] = votesByWeight[currentWeight][voteIndex];
                currentIndex++;

                if (currentIndex >= votesToReturnLength) {
                    return _votes;
                }
            }

            // Find the next highest vote
            currentWeight = previousWeight(currentWeight);
        }
    }

    /**
     * @notice Fetch the current list of top votes
     * @return Returns a sorted list of top votes
     */
    function topVotes() public view returns (Vote[] memory) {
        return topVotes(maxPoolsLength);
    }

    /**
     * @notice Fetch a sorted list of top votes
     * @param length The number of top votes to fetch (should exceed maxPoolsLength limit)
     * @return Returns a sorted list of top votes
     */
    function topVotes(uint256 length) public view returns (Vote[] memory) {
        uint256 votesToReturnLength = Math.min(length, maxPoolsLength);
        return votes(votesToReturnLength);
    }

    /**
     * @notice Fetch the combined absolute weight of all top votes
     * @return Returns the summation of top weights
     */
    function topVotesWeight() public view returns (uint256) {
        Vote[] memory _topVotes = topVotes();
        uint256 totalWeight;
        for (uint256 voteIndex; voteIndex < _topVotes.length; voteIndex++) {
            Vote memory vote = _topVotes[voteIndex];
            totalWeight += Math.abs(vote.weight);
        }
        return totalWeight;
    }

    /**
     * @notice Fetch a list of all votes for an account
     * @param accountAddress The address to fetch votes for
     * @return Returns a list of votes
     */
    function votesByAccount(address accountAddress)
        public
        view
        returns (Vote[] memory)
    {
        uint256 votesLength = votesLengthByAccount[accountAddress];
        Vote[] memory _votes = new Vote[](votesLength);
        for (uint256 voteIndex; voteIndex < votesLength; voteIndex++) {
            _votes[voteIndex] = accountVoteByIndex[accountAddress][voteIndex];
        }
        return _votes;
    }

    /**
     * @notice Fetch total vote weight available to the protocol
     * @return Returns total vote weight
     */
    function totalVoteWeight() public view returns (uint256) {
        return ve.balanceOfNFT(tokenId);
    }

    /*******************************************************
     *                  Binary tree traversal
     *******************************************************/

    /**
     * @notice Given a weight find the next highest weight
     * @param weight Weight node
     */
    function nextWeight(uint256 weight) public view returns (uint256) {
        return tree.next(weight);
    }

    /**
     * @notice Given a weight find the next lowest weight
     * @param weight Weight node
     */
    function previousWeight(uint256 weight) public view returns (uint256) {
        return tree.prev(weight);
    }

    /**
     * @notice Check to see if a weight node exists
     * @param weight Weight node
     */
    function weightExists(uint256 weight) public view returns (bool) {
        return tree.exists(weight);
    }

    /**
     * @notice Find the highest value weight node
     */
    function highestWeight() public view returns (uint256) {
        return tree.last();
    }

    /**
     * @notice Find the lowest value weight node
     */
    function lowestWeight() public view returns (uint256) {
        return tree.first();
    }

    /**
     * @notice Insert weight node into binary search tree
     */
    function insertWeight(uint256 weight) internal {
        tree.insert(weight);
    }

    /**
     * @notice Remove weight node from binary search tree
     */
    function removeWeight(uint256 weight) internal {
        tree.remove(weight);
    }

    /*******************************************************
     *                       Settings
     *******************************************************/

    /**
     * @notice Set maximum number of pools to be included in the vote
     * @param _maxPoolsLength The maximum number of top pools to be included in the vote
     * @dev This number is important as Solidly has intensive gas constraints when voting
     */
    function setMaxPoolsLength(uint256 _maxPoolsLength)
        external
        onlyGovernance
    {
        maxPoolsLength = _maxPoolsLength;
    }

    /**
     * @notice Set maximum number of unique pool votes per account
     * @param _maxVotesPerAccount The maximum number of pool votes allowed per account
     */
    function setMaxVotesPerAccount(uint256 _maxVotesPerAccount)
        external
        onlyGovernance
    {
        maxVotesPerAccount = _maxVotesPerAccount;
    }

    /**
     * @notice Set time window for voting snapshot submission
     */
    function setWindow(uint256 _window) external onlyGovernance {
        window = _window;
    }

    /**
     * @notice Set a vote delegate for an account
     * @param voteDelegateAddress The address of the new vote delegate
     */
    function setVoteDelegate(address voteDelegateAddress) external {
        voteDelegateByAccount[msg.sender] = voteDelegateAddress;
    }

    /**
     * @notice Clear a vote delegate for an account
     */
    function clearVoteDelegate() external {
        delete voteDelegateByAccount[msg.sender];
    }
}
