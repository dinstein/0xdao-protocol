// SPDX-License-Identifier: NONE

pragma solidity 0.8.11;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./ProxyImplementation.sol";
import "./Governable.sol";

import "./interfaces/IOxPool.sol";
import "./interfaces/IVoterProxy.sol";
import "./interfaces/IOxPoolFactory.sol";
import "./interfaces/IOxLens.sol";
import "./interfaces/IOxSolid.sol";
import "./interfaces/IMultiRewards.sol";
import "./interfaces/ICvlOxd.sol";
import "./interfaces/IGauge.sol";
import "./interfaces/IOxd.sol";

contract RewardsDistributor is Governable, ProxyImplementation {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    address public voterProxy;

    address public oxdLockPool;

    address public oxSolidRewardsPoolAddress;

    uint256 public basis = 10000;

    uint256 public oxdRate = 500;

    uint256 public oxSolidRate = 1000;

    uint256 public treasuryRate = 100; // TODO: for testing purposes. Will change to default 0 for deployment

    // For OXD/FTM & oxSOLID/SOLID LPs
    uint256 public ecosystemLPRate = 0; // TODO: for testing purposes. Will change to default 0 for deployment

    address[] public incentivizedPools;

    mapping(address => uint256) public incentivizedPoolWeights;

    uint256 incentivizedPoolWeightTotal;

    bool public partnersReceiveCvlOXD;

    address public oxLensAddress;

    mapping(address => bool) public operator;

    event OperatorStatus(address candidate, bool status);

    modifier onlyGovernanceOrOperator() {
        require(
            operator[msg.sender] ||
                msg.sender == governanceAddress ||
                msg.sender == voterProxy,
            "Only the governance or operator may perform this action"
        );
        _;
    }

    struct StakerStreams {
        uint256 oxdAmount;
        uint256 oxSolidAmount;
        uint256 treasuryAmount;
        uint256 LPAmount;
        uint256 partnerAmount;
        uint256 ecosystemLPAmount;
    }

    struct EcosystemLPWeights {
        address stakingAddress;
        uint256 weight;
    }

    /**
     * @notice Initialize proxy storage
     */
    function initializeProxyStorage(address _voterProxy)
        public
        checkProxyInitialized
    {
        // From Governable
        governanceAddress = msg.sender;
        voterProxy = _voterProxy;
    }

    // Don't need name change since the one in proxy takes different inputs
    function initialize(
        address _oxdLockPool,
        address _oxSolidRewardsPoolAddress,
        address _oxLensAddress
    ) external onlyGovernance {
        require(oxdLockPool == address(0), "Already initialized");

        oxdLockPool = _oxdLockPool;
        oxSolidRewardsPoolAddress = _oxSolidRewardsPoolAddress;

        oxLensAddress = _oxLensAddress;
    }

    /* ========== Admin Actions ========== */

    function setOperator(address candidate, bool status)
        external
        onlyGovernance
    {
        require(
            operator[candidate] != status,
            "Candidate already in this state"
        );
        operator[candidate] = status;
        emit OperatorStatus(candidate, status);
    }

    function setOxdLockPool(address _oxdLockPool) external onlyGovernance {
        oxdLockPool = _oxdLockPool;
    }

    function setOxSolidRewardsPool(address _oxSolidRewardsPoolAddress)
        external
        onlyGovernance
    {
        oxSolidRewardsPoolAddress = _oxSolidRewardsPoolAddress;
    }

    function setTreasuryRate(uint256 _treasuryRate) external onlyGovernance {
        treasuryRate = _treasuryRate;
    }

    function setPartnersReceiveCvlOXD(bool _partnersReceiveCvlOXD)
        external
        onlyGovernance
    {
        partnersReceiveCvlOXD = _partnersReceiveCvlOXD;
    }

    function setEcosystemLPRewards(
        uint256 _ecosystemLPRate,
        address[] calldata _incentivizedPools,
        uint256[] calldata _incentivizedPoolWeights
    ) external onlyGovernance {
        require(
            _incentivizedPools.length == _incentivizedPoolWeights.length,
            "Different amounts of pools and weights"
        );
        ecosystemLPRate = _ecosystemLPRate;
        incentivizedPools = _incentivizedPools;
        uint256 _incentivizedPoolWeightTotal;
        for (uint256 i; i < _incentivizedPools.length; i++) {
            incentivizedPoolWeights[
                _incentivizedPools[i]
            ] = _incentivizedPoolWeights[i];
            _incentivizedPoolWeightTotal += _incentivizedPoolWeights[i];
        }
        incentivizedPoolWeightTotal = _incentivizedPoolWeightTotal;
    }

    /* ========== Staking Pool Actions ========== */

    function addReward(
        address stakingAddress,
        address _rewardsToken,
        uint256 _rewardsDuration
    ) external onlyGovernanceOrOperator {
        IMultiRewards(stakingAddress).addReward(
            _rewardsToken,
            address(this),
            _rewardsDuration
        );
    }

    function notifyRewardAmount(
        address stakingAddress,
        address rewardTokenAddress,
        uint256 amount
    ) external onlyGovernanceOrOperator {
        if (amount == 0) {
            return;
        }
        address solidAddress = IOxLens(oxLensAddress).solidAddress(); //gas savings on ssload

        StakerStreams memory rewardStreams; //to avoid stack too deep

        // All bribes and fees go to oxSOLID stakers and partners who stake oxSOLID if it's whitelisted in tokensAllowlist
        // stored in rewardsDistributor if not whitelist (just so we don't transfer weird tokens down the line)
        // this also handles SOLID rebases that's passed here as oxSOLID
        if (rewardTokenAddress != solidAddress) {
            if (
                IOxLens(oxLensAddress).tokensAllowlist().tokenIsAllowed(
                    rewardTokenAddress
                )
            ) {
                (
                    rewardStreams.oxSolidAmount,
                    rewardStreams.partnerAmount
                ) = calculatePartnerSlice(amount);
                _notifyRewardAmount(
                    oxSolidRewardsPoolAddress,
                    rewardTokenAddress,
                    rewardStreams.oxSolidAmount
                );

                _notifyRewardAmount(
                    partnersRewardsPoolAddress(),
                    rewardTokenAddress,
                    rewardStreams.partnerAmount
                );
            }

            return;
        }

        // If it's SOLID, distribute SOLID at 10% to oxSOLID stakers (and partners), 5% to OXD stakers, x% to treasury, x% to OXD/FTM & oxSOLID/SOLID LPs, and rest to LP (84%)
        address oxSolidAddress = IOxLens(oxLensAddress).oxSolidAddress();
        address oxdAddress = IOxLens(oxLensAddress).oxdAddress();
        IOxSolid oxSolid = IOxSolid(oxSolidAddress);

        rewardStreams.oxdAmount = amount.mul(oxdRate).div(basis); //5%
        rewardStreams.oxSolidAmount = amount.mul(oxSolidRate).div(basis); //10%
        rewardStreams.treasuryAmount = amount.mul(treasuryRate).div(basis); //x%
        rewardStreams.ecosystemLPAmount = amount.mul(ecosystemLPRate).div(
            basis
        ); //x%

        rewardStreams.LPAmount = amount
            .sub(rewardStreams.oxdAmount)
            .sub(rewardStreams.oxSolidAmount)
            .sub(rewardStreams.treasuryAmount)
            .sub(rewardStreams.ecosystemLPAmount);

        // Distribute SOLID claimed
        _notifyRewardAmount(
            stakingAddress,
            solidAddress,
            rewardStreams.LPAmount
        );

        // Ecosystem LP and oxSOLID stakers and Partners get SOLID emission in oxSOLID
        uint256 amountToLock = rewardStreams.ecosystemLPAmount.add(
            rewardStreams.oxdAmount
        );
        IERC20(solidAddress).approve(voterProxy, amountToLock);
        IVoterProxy(voterProxy).lockSolid(amountToLock);

        //distribute oxSOLID to vlOXD
        _notifyRewardAmount(
            oxdLockPool,
            oxSolidAddress,
            rewardStreams.oxdAmount
        );

        // Distribute ecosystem LP amount in oxSOLID according to set weights
        if (rewardStreams.ecosystemLPAmount > 0) {
            uint256 incentivizedPoolAmount;
            for (uint256 i; i < incentivizedPools.length; i++) {
                incentivizedPoolAmount = rewardStreams
                    .ecosystemLPAmount
                    .mul(basis)
                    .mul(incentivizedPoolWeights[incentivizedPools[i]])
                    .div(incentivizedPoolWeightTotal)
                    .div(basis);
                _notifyRewardAmount(
                    incentivizedPools[i],
                    oxSolidAddress,
                    incentivizedPoolAmount
                );
            }
        }

        IERC20(solidAddress).safeTransfer(
            treasuryAddress(),
            rewardStreams.treasuryAmount
        );

        // For oxSOLID stakers, distribute SOLID emission as SOLID
        (
            rewardStreams.oxSolidAmount,
            rewardStreams.partnerAmount
        ) = calculatePartnerSlice(rewardStreams.oxSolidAmount);
        _notifyRewardAmount(
            oxSolidRewardsPoolAddress,
            solidAddress,
            rewardStreams.oxSolidAmount
        );
        _notifyRewardAmount(
            partnersRewardsPoolAddress(),
            solidAddress,
            rewardStreams.partnerAmount
        );

        // Mint OXD and distribute according to tokenomics
        // oxSOLID lockers get OXD = minted * (oxSolid.totalSupply()/SOLID.totalSupply())
        // this ensures oxSOLID lockers are not diluted against other SOLID stakers
        // and prevents the %OXD emission oxSOLID stakers get isn't diluted below oxSOLID/SOLID.totalSupply()
        // partners get theirs with at a floor ratio of 2*oxSOLID/SOLID, until 25%, which reverts back to normal
        // oxSOLID lockers altogether are guaranteed a 5% floor in emissions
        // partners get their OXD in locked form, this is acheived with vlOXD coupons (cvlOXD) since vlOXD itself isn't transferrable
        IOxd(oxdAddress).mint(address(this), amount);
        {
            uint256 oxSolidRatioOfSOLID = oxSolid.totalSupply().mul(1e18).div(
                IERC20(solidAddress).totalSupply()
            ); // basis is not precise enough here, using 1e18

            (
                uint256 nonpartnerRatioOfSOLID,
                uint256 partnersRatioOfSOLID
            ) = calculatePartnerSlice(oxSolidRatioOfSOLID);
            partnersRatioOfSOLID = partnersRatioOfSOLID.mul(2); //partners get minted*(partner oxSOLID/SOLID)*2 as a floor until 25%
            if (partnersRatioOfSOLID.mul(basis).div(1e18) > 2500) {
                partnersRatioOfSOLID = (
                    partnersRatioOfSOLID.div(2).sub(
                        (uint256(1250).mul(1e18)).div(basis)
                    )
                ).mul(7500).div(8750).add(uint256(2500).mul(1e18).div(basis)); // if above 25%, partnersRatioOfSOLID = ((partner oxSOLID/SOLID supply) - 0.125) * 0.75/0.875 + 0.25
            } else if (
                // oxSOLID stakers always get at least 5% of OXD emissions
                (nonpartnerRatioOfSOLID.add(partnersRatioOfSOLID))
                    .mul(basis)
                    .div(1e18) < 500
            ) {
                nonpartnerRatioOfSOLID = uint256(500).mul(1e18).div(basis).div(
                    3
                ); // Partners always have 2x weight against nonpartners if they're only getting 5% (5% < 25%)
                partnersRatioOfSOLID = nonpartnerRatioOfSOLID.mul(2);
            }

            rewardStreams.oxSolidAmount = amount
                .mul(nonpartnerRatioOfSOLID)
                .div(1e18);
            rewardStreams.partnerAmount = amount.mul(partnersRatioOfSOLID).div(
                1e18
            );
        }

        _notifyRewardAmount(
            oxSolidRewardsPoolAddress,
            oxdAddress,
            rewardStreams.oxSolidAmount
        );

        if (partnersReceiveCvlOXD) {
            // Mint cvlOXD and distribute to partnersRewardsPool
            address _cvlOxdAddress = cvlOxdAddress();
            IERC20(oxdAddress).approve(
                _cvlOxdAddress,
                rewardStreams.partnerAmount
            );
            ICvlOxd(_cvlOxdAddress).mint(
                address(this),
                rewardStreams.partnerAmount
            );
            _notifyRewardAmount(
                partnersRewardsPoolAddress(),
                _cvlOxdAddress,
                rewardStreams.partnerAmount
            );
        } else {
            _notifyRewardAmount(
                partnersRewardsPoolAddress(),
                oxdAddress,
                rewardStreams.partnerAmount
            );
        }

        rewardStreams.treasuryAmount = amount
            .sub(rewardStreams.oxSolidAmount)
            .sub(rewardStreams.partnerAmount)
            .mul(treasuryRate)
            .div(basis);

        rewardStreams.LPAmount = amount
            .sub(rewardStreams.oxSolidAmount)
            .sub(rewardStreams.partnerAmount)
            .sub(rewardStreams.treasuryAmount);

        _notifyRewardAmount(stakingAddress, oxdAddress, rewardStreams.LPAmount);
        IERC20(oxdAddress).safeTransfer(
            treasuryAddress(),
            rewardStreams.treasuryAmount
        );
    }

    /**
     * @notice To distribute stored bribed tokens that's newly whitelisted to oxSOLID stakers and Partners
     * @param  rewardTokenAddress reward token address
     * @dev no auth needed since it only transfers whitelisted addresses
     */
    function notifyStoredRewardAmount(address rewardTokenAddress) external {
        require(
            IOxLens(oxLensAddress).tokensAllowlist().tokenIsAllowed(
                rewardTokenAddress
            ),
            "Token is not whitelisted"
        );
        // Get amount of rewards stored in this address
        uint256 amount = IERC20(rewardTokenAddress).balanceOf(address(this));

        StakerStreams memory rewardStreams;

        (
            rewardStreams.oxSolidAmount,
            rewardStreams.partnerAmount
        ) = calculatePartnerSlice(amount);

        _notifyRewardAmount(
            oxSolidRewardsPoolAddress,
            rewardTokenAddress,
            rewardStreams.oxSolidAmount
        );

        _notifyRewardAmount(
            partnersRewardsPoolAddress(),
            rewardTokenAddress,
            rewardStreams.partnerAmount
        );
    }

    function _notifyRewardAmount(
        address stakingAddress,
        address rewardToken,
        uint256 amount
    ) internal {
        if (amount == 0) {
            return;
        }
        address rewardsDistributorAddress = IMultiRewards(stakingAddress)
            .rewardData(rewardToken)
            .rewardsDistributor;
        bool rewardExists = rewardsDistributorAddress != address(0);
        if (!rewardExists) {
            IMultiRewards(stakingAddress).addReward(
                rewardToken,
                address(this),
                604800 // 1 week
            );
        }

        IERC20(rewardToken).approve(stakingAddress, amount);
        IMultiRewards(stakingAddress).notifyRewardAmount(rewardToken, amount);
    }

    function setRewardsDuration(
        address stakingAddress,
        address _rewardsToken,
        uint256 _rewardsDuration
    ) external onlyGovernanceOrOperator {
        IMultiRewards(stakingAddress).setRewardsDuration(
            _rewardsToken,
            _rewardsDuration
        );
    }

    function harvestAndDistributeLPRewards(address[] calldata oxPools)
        external
        onlyGovernanceOrOperator
    {
        address gauge;
        address staking;

        for (uint256 i; i < oxPools.length; i++) {
            gauge = IOxPool(oxPools[i]).gaugeAddress();
            staking = IOxPool(oxPools[i]).stakingAddress();
            uint256 rewardsLength = IGauge(gauge).rewardsListLength();
            address[] memory rewards = new address[](rewardsLength);

            for (uint256 j; j < rewardsLength; j++) {
                rewards[j] = IGauge(gauge).rewards(j);
            }

            IVoterProxy(voterProxy).getRewardFromGauge(gauge, staking, rewards);
        }
    }

    /* ========== Token Recovery ========== */

    function recoverERC20FromStaking(
        address stakingAddress,
        address tokenAddress
    ) external {
        uint256 amount = IERC20(tokenAddress).balanceOf(stakingAddress);
        IMultiRewards(stakingAddress).recoverERC20(tokenAddress, amount);
        recoverERC20(tokenAddress);
    }

    function recoverERC20(address tokenAddress) public {
        uint256 amount = IERC20(tokenAddress).balanceOf(address(this));
        IERC20(tokenAddress).safeTransfer(governanceAddress, amount);
    }

    /* ========== Helper View Functions ========== */

    function oxLens() internal view returns (IOxLens) {
        return IOxLens(oxLensAddress);
    }

    function partnersRewardsPoolAddress() internal view returns (address) {
        return oxLens().partnersRewardsPoolAddress();
    }

    function treasuryAddress() internal view returns (address) {
        return oxLens().treasuryAddress();
    }

    function cvlOxdAddress() internal view returns (address) {
        return oxLens().cvlOxdAddress();
    }

    function calculatePartnerSlice(uint256 amount)
        internal
        view
        returns (uint256 oxSolidAmount, uint256 partnerAmount)
    {
        uint256 stakedSoxSolid = IMultiRewards(oxSolidRewardsPoolAddress)
            .totalSupply();
        uint256 stakedPoxSolid = IMultiRewards(partnersRewardsPoolAddress())
            .totalSupply();

        uint256 totalStakedOxSolid = stakedSoxSolid.add(stakedPoxSolid);
        totalStakedOxSolid = (totalStakedOxSolid != 0 ? totalStakedOxSolid : 1); //no divide by 0

        oxSolidAmount = amount
            .mul(basis)
            .mul(stakedSoxSolid)
            .div(totalStakedOxSolid)
            .div(basis);

        partnerAmount = amount - oxSolidAmount;
    }
}
