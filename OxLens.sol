// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "./ProxyImplementation.sol";

import "./interfaces/IMultiRewards.sol";
import "./interfaces/IOxd.sol";
import "./interfaces/IVlOxd.sol";
import "./interfaces/IOxSolid.sol";
import "./interfaces/IOxPool.sol";
import "./interfaces/IOxPoolFactory.sol";
import "./interfaces/ISolid.sol";
import "./interfaces/ISolidlyLens.sol";
import "./interfaces/IUserProxy.sol";
import "./interfaces/IUserProxyFactory.sol";
import "./interfaces/IVe.sol";
import "./interfaces/IVoterProxy.sol";
import "./interfaces/IVotingSnapshot.sol";
import "./interfaces/IPartnersRewards.sol";
import "./interfaces/IOxdV1Redeem.sol";
import "./interfaces/IOxdV1Rewards.sol";
import "./interfaces/ITokensAllowlist.sol";

/**
 * @title Primary view interface for protocol
 * @author 0xDAO
 * @dev This is the main contract used by the front-end to read protocol and user position data
 * @dev Other protocol contracts also use oxLens as a primary source of truth
 * @dev All data in this contract is read-only
 */
contract OxLens is ProxyImplementation {
    /*******************************************************
     *                     Configuration
     *******************************************************/

    // Public addresses
    address public gaugesFactoryAddress;
    address public minterAddress;
    address public oxPoolFactoryAddress;
    address public oxdAddress;
    address public oxSolidAddress;
    address public oxSolidRewardsPoolAddress;
    address public partnersRewardsPoolAddress;
    address public poolsFactoryAddress;
    address public rewardsDistributorAddress;
    address public solidAddress;
    address public solidlyLensAddress;
    address public treasuryAddress;
    address public userProxyFactoryAddress;
    address public userProxyInterfaceAddress;
    address public veAddress;
    address public vlOxdAddress;
    address public voterProxyAddress;
    address public voterAddress;
    address public votingSnapshotAddress;
    address public oxdV1RewardsAddress;
    address public oxdV1RedeemAddress;
    address public oxdV1Address;
    address public tokensAllowlistAddress;

    /**
     * Interface helpers --these are also user facing, however they are only meant to be consumed
     * by other contracts and are provided as a convenience. In most cases interfaces are kept as internal.
     */
    IMultiRewards public oxSolidRewardsPool;
    IOxd public oxd;
    IVlOxd public vlOxd;
    IOxPoolFactory public oxPoolFactory;
    IOxSolid public oxSolid;
    ISolid public solid;
    ISolidlyLens public solidlyLens;
    IUserProxyFactory public userProxyFactory;
    IVe public ve;
    IVoterProxy public voterProxy;
    IVotingSnapshot public votingSnapshot;
    ITokensAllowlist public tokensAllowlist;

    // Structs
    struct OxPoolData {
        address id;
        address stakingAddress;
        ISolidlyLens.Pool poolData;
    }
    struct ProtocolAddresses {
        address oxPoolFactoryAddress;
        address solidlyLensAddress;
        address oxdAddress;
        address vlOxdAddress;
        address oxSolidAddress;
        address voterProxyAddress;
        address solidAddress;
        address voterAddress;
        address poolsFactoryAddress;
        address gaugesFactoryAddress;
        address minterAddress;
        address veAddress;
        address userProxyInterfaceAddress;
        address votingSnapshotAddress;
        address oxdV1RewardsAddress;
        address oxdV1RedeemAddress;
        address oxdV1Address;
        address tokensAllowlistAddress;
    }
    struct UserPosition {
        address userProxyAddress;
        uint256 veTotalBalanceOf;
        ISolidlyLens.PositionVe[] vePositions;
        ISolidlyLens.PositionPool[] poolsPositions;
        IUserProxy.PositionStakingPool[] stakingPools;
        uint256 oxSolidBalanceOf;
        uint256 stakedOxSolidBalanceOf;
        IUserProxy.RewardToken[] oxSolidRewardPoolPosition;
        uint256 oxdV1StakedOxSolidStakableAmount;
        uint256 oxdV1StakedOxSolidBalanceOf;
        IUserProxy.RewardToken[] oxdV1OxSolidRewardPoolPosition;
        uint256 oxdBalanceOf;
        uint256 solidBalanceOf;
        uint256 vlOxdBalanceOf;
        IVlOxd.LocksData vlOxdLocksData;
        IUserProxy.RewardToken[] vlOxdRewardPoolPosition;
        VotesData votesData;
        uint256 oxdV1BalanceOf;
    }
    struct VotesData {
        address delegateAddress;
        uint256 weightTotal;
        uint256 weightUsed;
        uint256 weightAvailable;
        IVotingSnapshot.Vote[] votes;
    }
    struct StakingPoolRewardTokens {
        address stakingPoolAddress;
        IUserProxy.RewardToken[] rewardTokens;
    }

    function initializeProxyStorage(
        address _oxPoolFactoryAddress,
        address _userProxyFactoryAddress,
        address _solidlyLensAddress,
        address _oxdAddress,
        address _vlOxdAddress,
        address _oxSolidAddress,
        address _oxSolidRewardsPoolAddress,
        address _rewardsDistributorAddress,
        address _partnersRewardsPoolAddress,
        address _userProxyInterfaceAddress,
        address _oxdV1RewardsAddress,
        address _oxdV1RedeemAddress
    ) public checkProxyInitialized {
        treasuryAddress = msg.sender; // TODO: Hardcode/replace

        // Set addresses and interfaces
        solidlyLensAddress = _solidlyLensAddress;
        solidlyLens = ISolidlyLens(solidlyLensAddress);
        gaugesFactoryAddress = solidlyLens.gaugesFactoryAddress();
        minterAddress = solidlyLens.minterAddress();
        oxdAddress = _oxdAddress;
        oxd = IOxd(oxdAddress);
        oxPoolFactoryAddress = _oxPoolFactoryAddress;
        oxPoolFactory = IOxPoolFactory(oxPoolFactoryAddress);
        oxSolidAddress = _oxSolidAddress;
        oxSolid = IOxSolid(oxSolidAddress);
        oxSolidRewardsPoolAddress = _oxSolidRewardsPoolAddress;
        oxSolidRewardsPool = IMultiRewards(oxSolidRewardsPoolAddress);
        partnersRewardsPoolAddress = _partnersRewardsPoolAddress;
        poolsFactoryAddress = solidlyLens.poolsFactoryAddress();
        rewardsDistributorAddress = _rewardsDistributorAddress;
        solidAddress = solidlyLens.solidAddress();
        solid = ISolid(solidAddress);
        userProxyFactoryAddress = _userProxyFactoryAddress;
        userProxyFactory = IUserProxyFactory(userProxyFactoryAddress);
        userProxyInterfaceAddress = _userProxyInterfaceAddress;
        veAddress = solidlyLens.veAddress();
        ve = IVe(veAddress);
        vlOxdAddress = _vlOxdAddress;
        vlOxd = IVlOxd(vlOxdAddress);
        voterProxyAddress = oxPoolFactory.voterProxyAddress();
        voterProxy = IVoterProxy(voterProxyAddress);
        voterAddress = solidlyLens.voterAddress();
        votingSnapshotAddress = voterProxy.votingSnapshotAddress();
        votingSnapshot = IVotingSnapshot(votingSnapshotAddress);
        oxdV1RewardsAddress = _oxdV1RewardsAddress;
        oxdV1RedeemAddress = _oxdV1RedeemAddress;
        oxdV1Address = address(IOxdV1Redeem(_oxdV1RedeemAddress).oxdV1());
        tokensAllowlistAddress = oxPoolFactory.tokensAllowlist();
        tokensAllowlist = ITokensAllowlist(tokensAllowlistAddress);
    }

    /*******************************************************
     *                     Protocol metadata
     *******************************************************/

    /**
     * @notice Fetch metadata about Solidly and 0xDAO
     */
    function protocolAddresses()
        external
        view
        returns (ProtocolAddresses memory)
    {
        return
            ProtocolAddresses({
                oxPoolFactoryAddress: oxPoolFactoryAddress,
                solidlyLensAddress: solidlyLensAddress,
                oxdAddress: oxdAddress,
                vlOxdAddress: vlOxdAddress,
                oxSolidAddress: oxSolidAddress,
                voterProxyAddress: voterProxyAddress,
                solidAddress: solidAddress,
                voterAddress: voterAddress,
                poolsFactoryAddress: poolsFactoryAddress,
                gaugesFactoryAddress: gaugesFactoryAddress,
                minterAddress: minterAddress,
                veAddress: veAddress,
                userProxyInterfaceAddress: userProxyInterfaceAddress,
                votingSnapshotAddress: votingSnapshotAddress,
                oxdV1RewardsAddress: oxdV1RewardsAddress,
                oxdV1RedeemAddress: oxdV1RedeemAddress,
                oxdV1Address: oxdV1Address,
                tokensAllowlistAddress: tokensAllowlistAddress
            });
    }

    /**
     * @notice OXD total supply
     */
    function oxdTotalSupply() external view returns (uint256) {
        return IERC20(oxdAddress).totalSupply();
    }

    /**
     * @notice Fetch VoterProxy's primary token ID
     */
    function tokenId() external view returns (uint256) {
        return voterProxy.primaryTokenId();
    }

    /**
     * @notice Fetch SOLID's inflation since inception
     */
    function solidInflationSinceInception() external view returns (uint256) {
        return voterProxy.solidInflationSinceInception();
    }

    /*******************************************************
     *                      Reward tokens
     *******************************************************/

    /**
     * @notice Fetch reward token earnings and position given an account address, staking pool address and rewards token address
     * @param accountAddress The account to fetch a position for
     * @param stakingPoolAddress Address of the staking pool
     * @param rewardTokenAddress Address of the reward token
     * @return Returns a list of reward token positions
     */
    function rewardTokenPositionOf(
        address accountAddress,
        address stakingPoolAddress,
        address rewardTokenAddress
    ) public view returns (IUserProxy.RewardToken memory) {
        address userProxyAddress = userProxyByAccount(accountAddress);
        IMultiRewards multiRewards = IMultiRewards(stakingPoolAddress);
        return
            IUserProxy.RewardToken({
                rewardTokenAddress: rewardTokenAddress,
                rewardRate: multiRewards
                    .rewardData(rewardTokenAddress)
                    .rewardRate,
                rewardPerToken: multiRewards.rewardPerToken(rewardTokenAddress),
                getRewardForDuration: multiRewards.getRewardForDuration(
                    rewardTokenAddress
                ),
                earned: multiRewards.earned(
                    userProxyAddress,
                    rewardTokenAddress
                )
            });
    }

    /**
     * @notice Fetch multiple reward token positions for an account and staking pool address
     * @param accountAddress The account to fetch positions for
     * @param stakingPoolAddress Address of the staking pool
     * @return Returns multiple staking pool positions assocaited with an account/pool
     */
    function rewardTokensPositionsOf(
        address accountAddress,
        address stakingPoolAddress
    ) public view returns (IUserProxy.RewardToken[] memory) {
        IMultiRewards multiRewards = IMultiRewards(stakingPoolAddress);
        uint256 rewardTokensLength = multiRewards.rewardTokensLength();

        IUserProxy.RewardToken[]
            memory _rewardTokensPositionsOf = new IUserProxy.RewardToken[](
                rewardTokensLength
            );

        for (
            uint256 rewardTokenIndex;
            rewardTokenIndex < rewardTokensLength;
            rewardTokenIndex++
        ) {
            address rewardTokenAddress = multiRewards.rewardTokens(
                rewardTokenIndex
            );
            _rewardTokensPositionsOf[rewardTokenIndex] = rewardTokenPositionOf(
                accountAddress,
                stakingPoolAddress,
                rewardTokenAddress
            );
        }
        return _rewardTokensPositionsOf;
    }

    /**
     * @notice Fetch all reward token positions given an account address
     * @param accountAddress The account to fetch positions for
     * @dev Utilizes a per-user staking pool position map to find positions with O(n) efficiency
     */
    function rewardTokensPositionsOf(address accountAddress)
        external
        view
        returns (StakingPoolRewardTokens[] memory)
    {
        address userProxyAddress = userProxyByAccount(accountAddress);
        address[] memory _stakingPoolsAddresses = IUserProxy(userProxyAddress)
            .stakingAddresses();
        StakingPoolRewardTokens[]
            memory stakingPoolsRewardsTokens = new StakingPoolRewardTokens[](
                _stakingPoolsAddresses.length
            );
        for (
            uint256 stakingPoolIndex;
            stakingPoolIndex <
            IUserProxy(userProxyAddress).stakingPoolsLength();
            stakingPoolIndex++
        ) {
            address stakingPoolAddress = _stakingPoolsAddresses[
                stakingPoolIndex
            ];
            stakingPoolsRewardsTokens[
                stakingPoolIndex
            ] = StakingPoolRewardTokens({
                stakingPoolAddress: stakingPoolAddress,
                rewardTokens: rewardTokensPositionsOf(
                    accountAddress,
                    stakingPoolAddress
                )
            });
        }
        return stakingPoolsRewardsTokens;
    }

    /*******************************************************
     *                     LP Positions
     *******************************************************/

    /**
     * @notice Solidly pools positions
     * @param accountAddress Account to fetch positions for
     */
    function poolsPositions(address accountAddress)
        external
        view
        returns (ISolidlyLens.PositionPool[] memory)
    {
        return solidlyLens.poolsPositionsOf(accountAddress);
    }

    /**
     * @notice Find a staking pool position for an account given an account address and staking pool address
     * @param accountAddress The account to fetch positions for
     * @param stakingPoolAddress The address of the staking pool to check
     */
    function stakingPoolPosition(
        address accountAddress,
        address stakingPoolAddress
    ) public view returns (IUserProxy.PositionStakingPool memory) {
        address userProxyAddress = userProxyByAccount(accountAddress);
        address oxPoolAddress = IMultiRewards(stakingPoolAddress)
            .stakingToken();
        uint256 balanceOf = IMultiRewards(stakingPoolAddress).balanceOf(
            userProxyAddress
        );
        address solidPoolAddress = IOxPool(oxPoolAddress).solidPoolAddress();

        IUserProxy.RewardToken[] memory rewardTokens = rewardTokensPositionsOf(
            accountAddress,
            stakingPoolAddress
        );

        return
            IUserProxy.PositionStakingPool({
                stakingPoolAddress: stakingPoolAddress,
                oxPoolAddress: oxPoolAddress,
                solidPoolAddress: solidPoolAddress,
                balanceOf: balanceOf,
                rewardTokens: rewardTokens
            });
    }

    /**
     * @notice Find all staking pool positions for msg.sender
     */
    function stakingPoolsPositions()
        external
        view
        returns (IUserProxy.PositionStakingPool[] memory)
    {
        return stakingPoolsPositions(msg.sender);
    }

    /**
     * @notice Find all staking pool positions given an account address
     * @param accountAddress The account to fetch positions for
     */
    function stakingPoolsPositions(address accountAddress)
        public
        view
        returns (IUserProxy.PositionStakingPool[] memory)
    {
        IUserProxy.PositionStakingPool[] memory stakingPositions;

        address userProxyAddress = userProxyByAccount(accountAddress);
        if (userProxyAddress == address(0)) {
            return stakingPositions;
        }

        address[] memory _stakingPoolsAddresses = IUserProxy(userProxyAddress)
            .stakingAddresses();

        stakingPositions = new IUserProxy.PositionStakingPool[](
            _stakingPoolsAddresses.length
        );

        for (
            uint256 stakingPoolAddressIdx;
            stakingPoolAddressIdx < _stakingPoolsAddresses.length;
            stakingPoolAddressIdx++
        ) {
            address stakingPoolAddress = _stakingPoolsAddresses[
                stakingPoolAddressIdx
            ];
            IUserProxy.PositionStakingPool
                memory stakingPosition = stakingPoolPosition(
                    accountAddress,
                    stakingPoolAddress
                );
            stakingPositions[stakingPoolAddressIdx] = stakingPosition;
        }
        return stakingPositions;
    }

    /*******************************************************
     *                   oxPools positions
     *******************************************************/

    /**
     * @notice Fetch the total number of synced oxPools
     */
    function oxPoolsLength() public view returns (uint256) {
        return oxPoolFactory.oxPoolsLength();
    }

    /**
     * @notice Fetch all oxPools addresses
     * @return Returns all oxPool addresses
     * @dev Warning: at some point this method will no longer work (we will run out of gas) and pagination must be used
     */
    function oxPoolsAddresses() public view returns (address[] memory) {
        uint256 _oxPoolsLength = oxPoolsLength();
        address[] memory _oxPoolsAddresses = new address[](_oxPoolsLength);
        for (uint256 oxPoolIdx; oxPoolIdx < _oxPoolsLength; oxPoolIdx++) {
            _oxPoolsAddresses[oxPoolIdx] = oxPoolFactory.oxPools(oxPoolIdx);
        }
        return _oxPoolsAddresses;
    }

    /**
     * @notice Find metadata about an oxPool given an oxPoolAddress
     * @param oxPoolAddress The address of the oxPool to fetch metadata for
     */
    function oxPoolData(address oxPoolAddress)
        public
        view
        returns (OxPoolData memory)
    {
        IOxPool oxPool = IOxPool(oxPoolAddress);
        address stakingAddress = oxPool.stakingAddress();
        address solidPoolAddress = oxPool.solidPoolAddress();
        ISolidlyLens.Pool memory poolData = solidlyLens.poolInfo(
            solidPoolAddress
        );
        return
            OxPoolData({
                id: oxPoolAddress,
                stakingAddress: stakingAddress,
                poolData: poolData
            });
    }

    /**
     * @notice Fetch oxPool metadata given an array of oxPool addresses
     * @param _oxPoolsAddresses A list of oxPool addresses
     * @dev This method is intended for pagination
     */
    function oxPoolsData(address[] memory _oxPoolsAddresses)
        public
        view
        returns (OxPoolData[] memory)
    {
        OxPoolData[] memory _oxPoolsData = new OxPoolData[](
            _oxPoolsAddresses.length
        );
        for (
            uint256 oxPoolIdx;
            oxPoolIdx < _oxPoolsAddresses.length;
            oxPoolIdx++
        ) {
            address oxPoolAddress = _oxPoolsAddresses[oxPoolIdx];
            _oxPoolsData[oxPoolIdx] = oxPoolData(oxPoolAddress);
        }
        return _oxPoolsData;
    }

    /**
     * @notice Find metadata for all oxPools
     * @dev Warning: at some point this method will no longer work (we will run out of gas) and pagination must be used
     * @return Returns metadata for all oxPools
     */
    function oxPoolsData() external view returns (OxPoolData[] memory) {
        address[] memory _oxPoolsAddresses = oxPoolsAddresses();
        return oxPoolsData(_oxPoolsAddresses);
    }

    /*******************************************************
     *                       Voting
     *******************************************************/

    /**
     * @notice Find voting metadata and positions for an account
     * @param accountAddress The address to fetch voting metadata for
     */
    function votePositionsOf(address accountAddress)
        public
        view
        returns (VotesData memory)
    {
        uint256 weightTotal = votingSnapshot.voteWeightTotalByAccount(
            accountAddress
        );
        uint256 weightUsed = votingSnapshot.voteWeightUsedByAccount(
            accountAddress
        );
        uint256 weightAvailable = votingSnapshot.voteWeightAvailableByAccount(
            accountAddress
        );
        address delegateAddress = votingSnapshot.voteDelegateByAccount(
            accountAddress
        );
        IVotingSnapshot.Vote[] memory votes = votingSnapshot.votesByAccount(
            accountAddress
        );
        return
            VotesData({
                delegateAddress: delegateAddress,
                weightTotal: weightTotal,
                weightUsed: weightUsed,
                weightAvailable: weightAvailable,
                votes: votes
            });
    }

    /*******************************************************
     *                   Solidly positions
     *******************************************************/

    /**
     * @notice Find the amount of SOLID owned by an account
     * @param accountAddress The address to check balance of
     * @return Returns SOLID balance of account
     */
    function solidBalanceOf(address accountAddress)
        public
        view
        returns (uint256)
    {
        return solid.balanceOf(accountAddress);
    }

    /*******************************************************
     *                    oxSOLID positions
     *******************************************************/

    /**
     * @notice Find the amount of oxSOLID owned by an account
     * @param accountAddress The address to check balance of
     * @return Returns oxSOLID balance of account
     */
    function oxSolidBalanceOf(address accountAddress)
        public
        view
        returns (uint256)
    {
        return oxSolid.balanceOf(accountAddress);
    }

    /**
     * @notice Find the amount of staked oxSOLID for an account
     * @param accountAddress The address to check staked balance of
     * @return stakedBalance Returns staked oxSOLID balance of account
     */
    function stakedOxSolidBalanceOf(address accountAddress)
        public
        view
        returns (uint256 stakedBalance)
    {
        address userProxyAddress = userProxyByAccount(accountAddress);
        if (isPartner(userProxyAddress)) {
            stakedBalance = IPartnersRewards(partnersRewardsPoolAddress)
                .balanceOf(userProxyAddress);
        } else {
            stakedBalance = oxSolidRewardsPool.balanceOf(userProxyAddress);
        }
        return stakedBalance;
    }

    /**
     * @notice Find the amount of oxSOLID staked in the OXDv1 rewards pool for an account
     * @param accountAddress The address to check staked balance of
     * @return stakedBalance Returns staked oxSOLID balance of account
     */
    function oxdV1StakedOxSolidBalanceOf(address accountAddress)
        public
        view
        returns (uint256 stakedBalance)
    {
        address userProxyAddress = userProxyByAccount(accountAddress);
        stakedBalance = IMultiRewards(oxdV1RewardsAddress).balanceOf(
            userProxyAddress
        );
        return stakedBalance;
    }

    /**
     * @notice Find the amount of oxSOLID that can be added to the OXDv1 rewards pool for an account
     * @param accountAddress The address to check staked balance of
     * @return stakableAmount Returns the additional stakable amount
     */
    function oxdV1StakedOxSolidStakableAmount(address accountAddress)
        public
        view
        returns (uint256 stakableAmount)
    {
        address userProxyAddress = userProxyByAccount(accountAddress);

        // get staked balance and stakingCap
        uint256 stakedBalance = IOxdV1Rewards(oxdV1RewardsAddress).balanceOf(
            userProxyAddress
        );
        uint256 stakingCap = IOxdV1Rewards(oxdV1RewardsAddress).stakingCap(
            userProxyAddress
        );

        // check stakingCap > stakedBalance to prevent reverts, returns 0 if otherwise
        if (stakingCap > stakedBalance) {
            return stakingCap - stakedBalance;
        }
    }

    /**
     * @notice Find oxSOLID reward pool data for an account
     * @param accountAddress The address to check reward pool data for
     */
    function oxSolidRewardPoolPosition(address accountAddress)
        public
        view
        returns (IUserProxy.RewardToken[] memory)
    {
        //determin partner status
        if (isProxyPartner(accountAddress)) {
            return
                rewardTokensPositionsOf(
                    accountAddress,
                    partnersRewardsPoolAddress
                );
        }
        return
            rewardTokensPositionsOf(accountAddress, oxSolidRewardsPoolAddress);
    }

    /*******************************************************
     *                    vlOXD positions
     *******************************************************/

    /**
     * @notice Fetch vlOXD metadata and locks for an account
     * @param accountAddress The address to check
     */
    function vlOxdLocksData(address accountAddress)
        public
        view
        returns (IVlOxd.LocksData memory)
    {
        uint256 total;
        uint256 unlockable;
        uint256 locked;
        IVlOxd.LockedBalance[] memory locks;
        (total, unlockable, locked, locks) = vlOxd.lockedBalances(
            accountAddress
        );
        return
            IVlOxd.LocksData({
                total: total,
                unlockable: unlockable,
                locked: locked,
                locks: locks
            });
    }

    /**
     * @notice Fetch vlOXD reward token positions for an account
     * @param accountAddress The address to check
     */
    function vlOxdRewardTokenPositionsOf(address accountAddress)
        public
        view
        returns (IUserProxy.RewardToken[] memory)
    {
        address userProxyAddress = userProxyByAccount(accountAddress);
        IVlOxd _vlOxd = vlOxd;
        uint256 rewardTokensLength = _vlOxd.rewardTokensLength();
        IVlOxd.EarnedData[] memory claimable = vlOxd.claimableRewards(
            userProxyAddress
        );
        IUserProxy.RewardToken[]
            memory _rewardTokensPositionsOf = new IUserProxy.RewardToken[](
                rewardTokensLength
            );

        for (
            uint256 rewardTokenIndex;
            rewardTokenIndex < rewardTokensLength;
            rewardTokenIndex++
        ) {
            address rewardTokenAddress = _vlOxd.rewardTokens(rewardTokenIndex);
            _rewardTokensPositionsOf[
                rewardTokenIndex
            ] = vlOxdRewardTokenPositionOf(accountAddress, rewardTokenAddress);
            _rewardTokensPositionsOf[rewardTokenIndex].earned = claimable[
                rewardTokenIndex
            ].amount;
        }
        return _rewardTokensPositionsOf;
    }

    /**
     * @notice Fetch vlOXD reward token position of a specific token address for an account
     * @param accountAddress The address to check
     * @param rewardTokenAddress The token to check
     */
    function vlOxdRewardTokenPositionOf(
        address accountAddress,
        address rewardTokenAddress
    ) public view returns (IUserProxy.RewardToken memory) {
        address userProxyAddress = userProxyByAccount(accountAddress);
        IVlOxd _vlOxd = vlOxd;

        return
            IUserProxy.RewardToken({
                rewardTokenAddress: rewardTokenAddress,
                rewardRate: _vlOxd.rewardData(rewardTokenAddress).rewardRate,
                rewardPerToken: _vlOxd.rewardPerToken(rewardTokenAddress),
                getRewardForDuration: _vlOxd.getRewardForDuration(
                    rewardTokenAddress
                ),
                earned: 0
            });
    }

    /*******************************************************
     *                     veNFT positions
     *******************************************************/

    /**
     * @notice Calculate total veNFT balance summation given an array of ve positions
     */
    function veTotalBalanceOf(ISolidlyLens.PositionVe[] memory positions)
        public
        pure
        returns (uint256)
    {
        uint256 _veotalBalanceOf;
        for (
            uint256 positionIdx;
            positionIdx < positions.length;
            positionIdx++
        ) {
            ISolidlyLens.PositionVe memory position = positions[positionIdx];
            _veotalBalanceOf += position.balanceOf;
        }
        return _veotalBalanceOf;
    }

    /*******************************************************
     *                   Global user positions
     *******************************************************/

    /**
     * @notice Find all positions for an account
     * @param accountAddress The address to check
     * @dev Warning: it's possible this may revert at some point (due to out-of-gas) if the user has too many positions
     */
    function positionsOf(address accountAddress)
        external
        view
        returns (UserPosition memory)
    {
        UserPosition memory _userPosition;
        address userProxyAddress = userProxyByAccount(accountAddress);
        //sectioning to avoid stack-too-deep (there has to be a std joke somewhere in here)
        //wrap yer thing to avoid stds
        {
            ISolidlyLens.PositionVe[] memory vePositions = solidlyLens
                .vePositionsOf(accountAddress);
            ISolidlyLens.PositionPool[] memory _poolsPositions = solidlyLens
                .poolsPositionsOf(accountAddress);
            IUserProxy.PositionStakingPool[]
                memory stakingPools = stakingPoolsPositions(accountAddress);

            uint256 _veTotalBalanceOf = veTotalBalanceOf(vePositions);
            uint256 _oxSolidBalanceOf = oxSolidBalanceOf(accountAddress);
            IUserProxy.RewardToken[]
                memory _oxSolidRewardPoolPosition = oxSolidRewardPoolPosition(
                    accountAddress
                );
            IUserProxy.RewardToken[]
                memory _oxdV1OxSolidRewardPoolPosition = rewardTokensPositionsOf(
                    accountAddress,
                    oxdV1RewardsAddress
                );

            _userPosition.userProxyAddress = userProxyAddress;
            _userPosition.veTotalBalanceOf = _veTotalBalanceOf;
            _userPosition.vePositions = vePositions;
            _userPosition.poolsPositions = _poolsPositions;
            _userPosition.stakingPools = stakingPools;
            _userPosition.oxSolidBalanceOf = _oxSolidBalanceOf;
            _userPosition
                .oxSolidRewardPoolPosition = _oxSolidRewardPoolPosition;
            _userPosition
                .oxdV1OxSolidRewardPoolPosition = _oxdV1OxSolidRewardPoolPosition;
        }
        {
            uint256 _solidBalanceOf = solidBalanceOf(accountAddress);
            uint256 oxdBalanceOf = IERC20(oxdAddress).balanceOf(accountAddress);
            uint256 oxdV1BalanceOf = IERC20(oxdV1Address).balanceOf(
                accountAddress
            );
            uint256 vlOxdBalanceOf = IVlOxd(vlOxdAddress).lockedBalanceOf(
                userProxyAddress
            );
            IUserProxy.RewardToken[]
                memory _vlOxdRewardPoolPosition = vlOxdRewardTokenPositionsOf(
                    accountAddress
                );

            uint256 _stakedOxSolidBalanceOf = stakedOxSolidBalanceOf(
                accountAddress
            );
            uint256 _oxdV1StakedOxSolidBalanceOf = oxdV1StakedOxSolidBalanceOf(
                accountAddress
            );
            IVlOxd.LocksData memory _vlOxdLocksData = vlOxdLocksData(
                userProxyAddress
            );
            VotesData memory votesData = votePositionsOf(userProxyAddress);

            uint256 _oxdV1StakedOxSolidStakableAmount = oxdV1StakedOxSolidStakableAmount(
                    accountAddress
                );

            _userPosition.stakedOxSolidBalanceOf = _stakedOxSolidBalanceOf;
            _userPosition
                .oxdV1StakedOxSolidBalanceOf = _oxdV1StakedOxSolidBalanceOf;
            _userPosition.oxdBalanceOf = oxdBalanceOf;
            _userPosition.solidBalanceOf = _solidBalanceOf;
            _userPosition.vlOxdBalanceOf = vlOxdBalanceOf;
            _userPosition.vlOxdLocksData = _vlOxdLocksData;
            _userPosition.vlOxdRewardPoolPosition = _vlOxdRewardPoolPosition;
            _userPosition.votesData = votesData;
            _userPosition.oxdV1BalanceOf = oxdV1BalanceOf;
            _userPosition
                .oxdV1StakedOxSolidStakableAmount = _oxdV1StakedOxSolidStakableAmount;
        }
        return _userPosition;
    }

    /*******************************************************
     *                      User Proxy
     *******************************************************/

    /**
     * @notice Given an account address fetch the user's UserProxy interface
     * @dev Internal convenience method
     */
    function userProxy(address accountAddress)
        internal
        view
        returns (IUserProxy)
    {
        address userProxyAddress = userProxyByAccount(accountAddress);
        return IUserProxy(userProxyAddress);
    }

    /**
     * @notice Fetch total number of user proxies
     */
    function userProxiesLength() public view returns (uint256) {
        return userProxyFactory.userProxiesLength();
    }

    /**
     * @notice Fetch a user's UserProxy address given an account address
     */
    function userProxyByAccount(address accountAddress)
        public
        view
        returns (address)
    {
        return userProxyFactory.userProxyByAccount(accountAddress);
    }

    /**
     * @notice Find a user proxy address given an index
     */
    function userProxyByIndex(uint256 index) public view returns (address) {
        return userProxyFactory.userProxyByIndex(index);
    }

    /*******************************************************
     *                    Helper utilities
     *******************************************************/

    /**
     * @notice Given an oxPoolAddress fetch the corresponding solid pool address
     */
    function solidPoolByOxPool(address oxPoolAddress)
        public
        view
        returns (address)
    {
        return oxPoolFactory.solidPoolByOxPool(oxPoolAddress);
    }

    /**
     * @notice Given a SOLID pool address fetch the corresponding oxPool address
     */
    function oxPoolBySolidPool(address solidPoolAddress)
        public
        view
        returns (address)
    {
        return oxPoolFactory.oxPoolBySolidPool(solidPoolAddress);
    }

    /**
     * @notice Given a SOLID pool address find the corresponding gauge address
     * @param solidPoolAddress Input address
     */
    function gaugeBySolidPool(address solidPoolAddress)
        public
        view
        returns (address)
    {
        return solidlyLens.gaugeAddressByPoolAddress(solidPoolAddress);
    }

    /**
     * @notice Given an oxPool address find the corresponding staking rewards address
     * @param oxPoolAddress Input address
     */
    function stakingRewardsByOxPool(address oxPoolAddress)
        public
        view
        returns (address)
    {
        IOxPool oxPool = IOxPool(oxPoolAddress);
        address stakingAddress = oxPool.stakingAddress();
        return stakingAddress;
    }

    /**
     * @notice Given a SOLID pool address find the corresponding staking pool address
     * @param solidPoolAddress Input address
     */
    function stakingRewardsBySolidPool(address solidPoolAddress)
        external
        view
        returns (address)
    {
        address oxPoolAddress = oxPoolBySolidPool(solidPoolAddress);
        address stakingAddress = stakingRewardsByOxPool(oxPoolAddress);
        return stakingAddress;
    }

    /**
     * @notice Determine whether or not a pool is a valid oxPool
     */
    function isOxPool(address oxPoolAddress) public view returns (bool) {
        return oxPoolFactory.isOxPool(oxPoolAddress);
    }

    /**
     * @notice Determine whether or not a given account address is a partner
     * @param userProxyAddress User proxy address
     */
    function isPartner(address userProxyAddress) public view returns (bool) {
        return
            IPartnersRewards(partnersRewardsPoolAddress).isPartner(
                userProxyAddress
            );
    }

    /**
     * @notice Determine whether or not a given user's proxy address is a partner
     * @param accountAddress User address
     */
    function isProxyPartner(address accountAddress) public view returns (bool) {
        address userProxyAddress = userProxyByAccount(accountAddress);
        return
            IPartnersRewards(partnersRewardsPoolAddress).isPartner(
                userProxyAddress
            );
    }
}
