// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;
// General imports
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "./Governable.sol";
import "./ProxyImplementation.sol";

// Interfaces
import "./interfaces/IGauge.sol";
import "./interfaces/IOxSolid.sol";
import "./interfaces/IOxPool.sol";
import "./interfaces/IOxPoolFactory.sol";
import "./interfaces/IRewardsDistributor.sol";
import "./interfaces/ISolid.sol";
import "./interfaces/ISolidBribe.sol";
import "./interfaces/ISolidGauge.sol";
import "./interfaces/ISolidPool.sol";
import "./interfaces/ISolidlyLens.sol";
import "./interfaces/ITokensAllowlist.sol";
import "./interfaces/IVe.sol";
import "./interfaces/IVoter.sol";
import "./interfaces/IVeDist.sol";

/**************************************************
 *                   Voter Proxy
 **************************************************/

contract VoterProxy is IERC721Receiver, Governable, ProxyImplementation {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    // Public addresses
    address public oxPoolFactoryAddress;
    address public oxSolidAddress;
    uint256 public primaryTokenId;
    address public rewardsDistributorAddress;
    address public solidAddress;
    address public veAddress;
    address public veDistAddress;
    address public votingSnapshotAddress;

    // Public vars
    uint256 public solidInflationSinceInception;

    // Internal addresses
    address internal voterProxyAddress;

    // Internal interfaces
    IVoter internal voter;
    IVe internal ve;
    IVeDist internal veDist;
    ITokensAllowlist internal tokensAllowlist;

    /**
     * @notice Initialize proxy storage
     */
    function initializeProxyStorage(
        address _veAddress,
        address _veDistAddress,
        address _tokensAllowlistAddress
    ) public checkProxyInitialized {
        // From Governable
        governanceAddress = msg.sender;

        // Set addresses
        veAddress = _veAddress;
        veDistAddress = _veDistAddress;

        // Set inflation
        solidInflationSinceInception = 1e18;

        // Set interfaces
        ve = IVe(veAddress);
        veDist = IVeDist(veDistAddress);
        voter = IVoter(voterAddress());
        tokensAllowlist = ITokensAllowlist(_tokensAllowlistAddress);
    }

    // Modifiers
    modifier onlyOxSolid() {
        require(msg.sender == oxSolidAddress, "Only oxSolid can deposit NFTs");
        _;
    }
    modifier onlyOxPool() {
        bool _isOxPool = IOxPoolFactory(oxPoolFactoryAddress).isOxPool(
            msg.sender
        );
        require(_isOxPool, "Only ox pools can stake");
        _;
    }
    modifier onlyGovernanceOrVotingSnapshot() {
        require(
            msg.sender == governanceAddress ||
                msg.sender == votingSnapshotAddress,
            "Only governance or voting snapshot"
        );
        _;
    }
    uint256 internal _unlocked = 1;
    modifier lock() {
        require(_unlocked == 1, "Reentrancy");
        _unlocked = 2;
        _;
        _unlocked = 1;
    }

    /**
     * @notice Initialization
     * @param _oxPoolFactoryAddress oxPool factory address
     * @param _oxSolidAddress oxSolid address
     * @dev Can only be initialized once
     */
    function initialize(
        address _oxPoolFactoryAddress,
        address _oxSolidAddress,
        address _votingSnapshotAddress
    ) public {
        bool notInitialized = oxPoolFactoryAddress == address(0);
        require(notInitialized, "Already initialized");

        // Set addresses and interfaces
        oxPoolFactoryAddress = _oxPoolFactoryAddress;
        oxSolidAddress = _oxSolidAddress;
        solidAddress = IVe(veAddress).token();
        voterProxyAddress = address(this);
        rewardsDistributorAddress = IOxPoolFactory(_oxPoolFactoryAddress)
            .rewardsDistributorAddress();
        votingSnapshotAddress = _votingSnapshotAddress;
    }

    /**************************************************
     *                  Gauge interactions
     **************************************************/

    /**
     * @notice Deposit Solidly LP into a gauge
     * @param solidPoolAddress Address of LP to deposit
     * @param amount Amount of LP to deposit
     */
    function depositInGauge(address solidPoolAddress, uint256 amount)
        public
        onlyOxPool
    {
        // Cannot deposit nothing
        require(amount > 0, "Nothing to deposit");

        // Find gauge address
        address gaugeAddress = voter.gauges(solidPoolAddress);

        // Allow gauge to spend Solidly LP
        ISolidPool solidPool = ISolidPool(solidPoolAddress);
        solidPool.approve(gaugeAddress, amount);

        // Deposit Solidly LP into gauge
        ISolidGauge(gaugeAddress).deposit(amount, primaryTokenId);
    }

    /**
     * @notice Withdraw Solidly LP from a gauge
     * @param solidPoolAddress Address of LP to withdraw
     * @param amount Amount of LP to withdraw
     */
    function withdrawFromGauge(address solidPoolAddress, uint256 amount)
        public
        onlyOxPool
    {
        require(amount > 0, "Nothing to withdraw");
        address gaugeAddress = voter.gauges(solidPoolAddress);
        ISolidGauge solidGauge = ISolidGauge(gaugeAddress);
        ISolidGauge(gaugeAddress).withdraw(amount);
        ISolidPool solidPool = ISolidPool(solidPoolAddress);
        solidPool.transfer(msg.sender, amount);
    }

    /**************************************************
     *                      Rewards
     **************************************************/

    /**
     * @notice Get fees from bribe
     * @param oxPoolAddress Address of oxPool
     */
    function getFeeTokensFromBribe(address oxPoolAddress)
        public
        returns (bool allClaimed)
    {
        IOxPool oxPool = IOxPool(oxPoolAddress);
        ISolidlyLens.Pool memory solidPoolInfo = oxPool.solidPoolInfo();
        address bribeAddress = solidPoolInfo.bribeAddress;
        address gaugeAddress = solidPoolInfo.gaugeAddress;

        // Skip if we have no votes in bribe
        if (ISolidBribe(bribeAddress).balanceOf(primaryTokenId) == 0) {
            return false;
        }

        address[] memory feeTokenAddresses = new address[](2);
        feeTokenAddresses[0] = solidPoolInfo.token0Address;
        feeTokenAddresses[1] = solidPoolInfo.token1Address;
        (allClaimed, ) = getRewardFromBribe(oxPoolAddress, feeTokenAddresses);
        if (allClaimed) {
            ISolidGauge(gaugeAddress).claimFees();
        }
    }

    /**
     * @notice Claims LP SOLID emissions and calls rewardsDistributor
     * @param oxPoolAddress the oxPool to claim for
     */
    function claimSolid(address oxPoolAddress)
        external
        returns (bool _claimSolid)
    {
        IOxPool oxPool = IOxPool(oxPoolAddress);
        address stakingAddress = oxPool.stakingAddress();
        ISolidlyLens.Pool memory solidPoolInfo = oxPool.solidPoolInfo();
        address gaugeAddress = solidPoolInfo.gaugeAddress;

        voter.distribute(gaugeAddress);
        _claimSolid = _batchCheckPointOrGetReward(gaugeAddress, solidAddress);

        if (_claimSolid) {
            address[] memory solidAddressInArray = new address[](1);
            solidAddressInArray[0] = solidAddress;

            IGauge(gaugeAddress).getReward(
                voterProxyAddress,
                solidAddressInArray
            );

            uint256 _solidEarned = IERC20(solidAddress).balanceOf(
                voterProxyAddress
            );
            if (_solidEarned > 0) {
                IERC20(solidAddress).safeTransfer(
                    rewardsDistributorAddress,
                    _solidEarned
                );
                IRewardsDistributor(rewardsDistributorAddress)
                    .notifyRewardAmount(
                        stakingAddress,
                        solidAddress,
                        _solidEarned
                    );
            }
        }
    }

    /**
     * @notice Claim bribes and notify rewards contract of new balances
     * @param oxPoolAddress oxPool address
     * @param _tokensAddresses Bribe tokens addresses
     */
    function getRewardFromBribe(
        address oxPoolAddress,
        address[] memory _tokensAddresses
    ) public returns (bool allClaimed, bool[] memory claimed) {
        // Establish addresses
        IOxPool oxPool = IOxPool(oxPoolAddress);
        address _stakingAddress = oxPool.stakingAddress();
        ISolidlyLens.Pool memory solidPoolInfo = oxPool.solidPoolInfo();
        address _bribeAddress = solidPoolInfo.bribeAddress;

        // New array to record whether a token's claimed
        claimed = new bool[](_tokensAddresses.length);

        // Preflight - check whether to batch checkpoints or to claim said token
        address[] memory _claimableAddresses;
        _claimableAddresses = new address[](_tokensAddresses.length);
        uint256 j;

        // Populate a new array with addresses that are ready to be claimed
        for (uint256 i; i < _tokensAddresses.length; i++) {
            if (
                _batchCheckPointOrGetReward(_bribeAddress, _tokensAddresses[i])
            ) {
                _claimableAddresses[j] = _tokensAddresses[i];
                claimed[j] = true;
                j++;
            }
        }
        // Clean up _claimableAddresses array, so we don't pass a bunch of address(0)s to ISolidBribe
        address[] memory claimableAddresses = new address[](j);
        for (uint256 k; k < j; k++) {
            claimableAddresses[k] = _claimableAddresses[k];
        }

        // Actually claim rewards that are deemed claimable
        if (claimableAddresses.length != 0) {
            ISolidBribe(_bribeAddress).getReward(
                primaryTokenId,
                claimableAddresses
            );
            // If everything was claimable, flag return to true
            if (claimableAddresses.length == _tokensAddresses.length) {
                if (
                    claimableAddresses[claimableAddresses.length - 1] !=
                    address(0)
                ) {
                    allClaimed = true;
                }
            }
        }

        // Transfer to rewardsDistributor and call notifyRewardAmount
        for (
            uint256 tokenIndex;
            tokenIndex < claimableAddresses.length;
            tokenIndex++
        ) {
            uint256 amount = IERC20(claimableAddresses[tokenIndex]).balanceOf(
                address(this)
            );
            if (amount != 0) {
                IERC20(claimableAddresses[tokenIndex]).safeTransfer(
                    rewardsDistributorAddress,
                    amount
                );
                IRewardsDistributor(rewardsDistributorAddress)
                    .notifyRewardAmount(
                        _stakingAddress,
                        claimableAddresses[tokenIndex],
                        amount
                    );
            }
        }
    }

    /**
     * @notice Fetch reward from oxPool given token addresses
     * @param oxPoolAddress Address of the oxPool
     * @param tokensAddresses Tokens to fetch rewards for
     */
    function getRewardFromOxPool(
        address oxPoolAddress,
        address[] memory tokensAddresses
    ) public {
        IOxPool oxPool = IOxPool(oxPoolAddress);
        address gaugeAddress = oxPool.gaugeAddress();
        address stakingAddress = oxPool.stakingAddress();
        getRewardFromGauge(gaugeAddress, stakingAddress, tokensAddresses);
    }

    /**
     * @notice Fetch reward from gauge
     * @param gaugeAddress Gauge address
     * @param stakingAddress Address of staking contract
     * @param tokensAddresses Tokens to fetch rewards for
     */
    function getRewardFromGauge(
        address gaugeAddress,
        address stakingAddress,
        address[] memory tokensAddresses
    ) public lock {
        ISolidGauge(gaugeAddress).getReward(address(this), tokensAddresses);
        for (
            uint256 tokenIndex;
            tokenIndex < tokensAddresses.length;
            tokenIndex++
        ) {
            uint256 amount = IERC20(tokensAddresses[tokenIndex]).balanceOf(
                address(this)
            );
            IRewardsDistributor(rewardsDistributorAddress).notifyRewardAmount(
                stakingAddress,
                tokensAddresses[tokenIndex],
                amount
            );
        }
    }

    /**
     * @notice Batch fetch reward
     * @param bribeAddress Address of bribe
     * @param tokenAddress Reward token address
     * @param lagLimit Number of indexes per batch
     * @dev This method is imporatnt because if we don't do this Solidly claiming can be bricked due to gas costs
     */
    function batchCheckPointOrGetReward(
        address bribeAddress,
        address tokenAddress,
        uint256 lagLimit
    ) public returns (bool _getReward) {
        if (tokenAddress == address(0)) {
            return _getReward; //returns false if address(0)
        }
        ISolidBribe bribe = ISolidBribe(bribeAddress);
        uint256 lastUpdateTime = bribe.lastUpdateTime(tokenAddress);
        uint256 priorSupplyIndex = bribe.getPriorSupplyIndex(lastUpdateTime);
        uint256 supplyNumCheckpoints = bribe.supplyNumCheckpoints();
        uint256 lag;
        if (supplyNumCheckpoints > priorSupplyIndex) {
            lag = supplyNumCheckpoints.sub(priorSupplyIndex);
        }
        if (lag > lagLimit) {
            bribe.batchRewardPerToken(
                tokenAddress,
                priorSupplyIndex.add(lagLimit)
            ); // costs about 250k gas, around 3% of an ftm block. Don't want to do too many since we need to chain these sometimes. Hardcoded to save some gas (probably don't need changing anyway)
        } else {
            _getReward = true;
        }
    }

    /**
     * @notice Internal reward batching
     * @param bribeAddress Address of bribe
     * @param tokenAddress Reward token address
     */
    function _batchCheckPointOrGetReward(
        address bribeAddress,
        address tokenAddress
    ) internal returns (bool _getReward) {
        uint256 lagLimit = tokensAllowlist.bribeSyncLagLimit();
        _getReward = batchCheckPointOrGetReward(
            bribeAddress,
            tokenAddress,
            lagLimit
        );
    }

    /**************************************************
     *                      Voting
     **************************************************/

    /**
     * @notice Submit vote to Solidly
     * @param poolVote Addresses of pools to vote on
     * @param weights Weights of pools to vote on
     */
    function vote(address[] memory poolVote, int256[] memory weights)
        external
        onlyGovernanceOrVotingSnapshot
    {
        voter.vote(primaryTokenId, poolVote, weights);
    }

    /**************************************************
     *               Ve Dillution mechanism
     **************************************************/

    /**
     * @notice Claims SOLID inflation for veNFT, logs inflation record, mints corresponding oxSOLID, and distributes oxSOLID
     */
    function claim() external {
        uint256 lockedAmount = ve.locked(primaryTokenId);
        uint256 inflationAmount = veDist.claim(primaryTokenId);
        solidInflationSinceInception = solidInflationSinceInception
            .mul(
                (inflationAmount.add(lockedAmount)).mul(1e18).div(lockedAmount)
            )
            .div(1e18);
        IOxSolid(oxSolidAddress).mint(voterProxyAddress, inflationAmount);
        IERC20(oxSolidAddress).safeTransfer(
            rewardsDistributorAddress,
            inflationAmount
        );
        IRewardsDistributor(rewardsDistributorAddress).notifyRewardAmount(
            voterProxyAddress,
            oxSolidAddress,
            inflationAmount
        );
    }

    /**************************************************
     *                 NFT Interactions
     **************************************************/

    /**
     * @notice Deposit and merge NFT
     * @param tokenId The token ID to deposit
     * @dev Note: Depositing is a one way/nonreversible action
     */
    function depositNft(uint256 tokenId) public onlyOxSolid {
        // Set primary token ID if it hasn't been set yet
        bool primaryTokenIdSet = primaryTokenId > 0;
        if (!primaryTokenIdSet) {
            primaryTokenId = tokenId;
        }

        // Transfer NFT from msg.sender to voter proxy (here)
        ve.safeTransferFrom(msg.sender, voterProxyAddress, tokenId);

        // If primary token ID is set, merge the NFT
        if (primaryTokenIdSet) {
            ve.merge(tokenId, primaryTokenId);
        }
    }

    /**
     * @notice Convert SOLID to veNFT and deposit for oxSOLID
     * @param amount The amount of SOLID to lock
     */
    function lockSolid(uint256 amount) external {
        ISolid solid = ISolid(solidAddress);
        solid.transferFrom(msg.sender, address(this), amount);
        uint256 allowance = solid.allowance(address(this), veAddress);
        if (allowance <= amount) {
            solid.approve(veAddress, amount);
        }
        uint256 lockTime = 4 * 365 * 86400; // 4 years
        uint256 tokenId = ve.create_lock(amount, lockTime);
        ve.merge(tokenId, primaryTokenId);
        IOxSolid(oxSolidAddress).mint(msg.sender, amount);
    }

    /**
     * @notice Don't do anything with direct NFT transfers
     */
    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    function voterAddress() public view returns (address) {
        return ve.voter();
    }

    /**************************************************
     *                   View methods
     **************************************************/

    /**
     * @notice Calculate amount of SOLID currently claimable by VoterProxy
     * @param gaugeAddress The address of the gauge VoterProxy has earned on
     */
    function solidEarned(address gaugeAddress) public view returns (uint256) {
        return IGauge(gaugeAddress).earned(solidAddress, address(this));
    }
}
