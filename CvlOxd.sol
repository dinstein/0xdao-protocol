// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IOxLens.sol";
import "./interfaces/IVlOxd.sol";
import "./interfaces/IUserProxy.sol";
import "./interfaces/IUserProxyFactory.sol";
import "./Governable.sol";
import "./ProxyImplementation.sol";

//Users will never have any cvlOXD balances with how distribution is currently implemented.
//Though this still technically allows users holding cvlOXD if the DAO votes on it
//Might be useful if we ever need to distribute vlOXD rewards as coupons in the future
//Whitelisted addresses can redeem cvlOXD into vlOXD for anyone (basically distributing vlOXD)
//Normal holders can only redeem cvlOXD into vlOXD for themselves
contract CvlOxd is ERC20, Governable, ProxyImplementation {
    address public minterAddress;
    IOxLens public oxLens;
    mapping(address => bool) whitelist;

    // Migrated from ERC20 due to being a ProxyImplementation
    string private _name;
    string private _symbol;

    /**
     * @dev Since this is meant to be a proxy's implementation, DO NOT implement logic in this constructor, use initializeProxyStorage() instead
     */
    constructor() ERC20("Vote Locked OXD Coupon", "cvlOXD") {}

    /**
     * @notice Initialize proxy storage
     */
    function initializeProxyStorage() public checkProxyInitialized {
        // From Governable
        governanceAddress = msg.sender;

        // From ERC20
        _name = "Vote Locked OXD Coupon";
        _symbol = "cvlOXD";
    }

    modifier onlyMinter() {
        require(
            msg.sender == minterAddress,
            "Ownable: caller is not the minter"
        );
        _;
    }

    /**
     * @dev Returns the name of the token.
     * @dev Migrated from ERC20 due to being a ProxyImplementation
     */
    function name() public view override returns (string memory) {
        return _name;
    }

    /**
     * @dev Returns the symbol of the token, usually a shorter version of the
     * name.
     * @dev Migrated from ERC20 due to being a ProxyImplementation
     */
    function symbol() public view override returns (string memory) {
        return _symbol;
    }

    function initialize(IOxLens _oxLens, address _minterAddress)
        external
        onlyGovernance
    {
        require(oxLens == IOxLens(address(0)), "Already initialized");
        oxLens = _oxLens;
        setMinter(_minterAddress);
    }

    // Minter is rewardsDistributor
    function setMinter(address _minterAddress) public onlyGovernance {
        minterAddress = _minterAddress;
    }

    function mint(address to, uint256 amount) public onlyMinter {
        IERC20(oxLens.oxdAddress()).transferFrom(
            msg.sender,
            address(this),
            amount
        );
        _mint(to, amount);
    }

    //whitelist is approved contracts that can distribute coupons, such as partnerRewardsPool
    function setWhitelist(address candidate, bool status)
        public
        onlyGovernance
    {
        whitelist[candidate] = status;
    }

    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal override {
        if (whitelist[sender]) {
            super._transfer(sender, recipient, amount);
            return;
        } else if (
            isUserProxy(msg.sender) //since userProxy can pass arbitury data, this doesn't really prevent people from calling it this way, but there's nothing to exploit since it'll just redeem the coupon to userProxy
        ) {
            redeem(amount);
            return;
        }
        revert("Coupons are not transferrable");
    }

    function redeem() external {
        redeem(msg.sender, balanceOf(msg.sender));
    }

    function redeem(uint256 amount) public {
        redeem(msg.sender, amount);
    }

    function redeem(address to, uint256 amount) public {
        require(
            whitelist[msg.sender] || to == msg.sender,
            "Coupons are not transferrable"
        );
        _burn(msg.sender, amount);
        IVlOxd vlOxd = IVlOxd(oxLens.vlOxdAddress());
        IERC20(oxLens.oxdAddress()).approve(address(vlOxd), amount);

        if (isUserProxy(msg.sender)) {
            vlOxd.lock(msg.sender, amount, 0);
        } else {
            address userProxyAddress = IUserProxyFactory(
                oxLens.userProxyFactoryAddress()
            ).userProxyByAccount(msg.sender);
            vlOxd.lock(userProxyAddress, amount, 0);
        }
    }

    /* ===== Internal View Functions =====*/
    function userProxyFactory() internal view returns (IUserProxyFactory) {
        return IUserProxyFactory(oxLens.userProxyFactoryAddress());
    }

    function isUserProxy(address account) internal view returns (bool) {
        return userProxyFactory().isUserProxy(account);
    }
}
