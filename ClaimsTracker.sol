// // SPDX-License-Identifier: MIT
// pragma solidity 0.8.11;

// /**
//  * @title ClaimsTracker
//  * @author 0xDAO
//  * @notice This contract keeps track of global and user token claims
//  * @dev This could be accomplished using subgraph but it's nice to have
//  *      access to this data on-chain and it's cheap enough to implement
//  */
// contract ClaimsTracker {
//     address public userProxyFactoryAddress;

//     // Global claims
//     address[] claimedTokensAddresses;
//     mapping(address => bool) public tokenClaimed;
//     mapping(address => uint256) public amountClaimedByToken;

//     // User claims
//     mapping(address => address[]) claimedTokensAddressesByAccount;
//     mapping(address => mapping(address => bool)) tokenClaimedByAccount;
//     mapping(address => mapping(address => uint256))
//         public amountClaimedByTokenByAccount;

//     /**
//      * @notice Register a token claim
//      * @param claimTokenAddress Address of the token claimed
//      * @param amount Amount of token claimed
//      * @param accountAddress Account that claimed the token
//      */
//     function registerClaim(
//         address claimTokenAddress,
//         uint256 amount,
//         address accountAddress
//     ) public {
//         // Global claim
//         if (!tokenClaimed[claimTokenAddress]) {
//             tokenClaimed[claimTokenAddress] = true;
//             claimedTokensAddresses.push(claimTokenAddress);
//         }
//         amountClaimedByToken[claimTokenAddress] += amount;

//         // User claim
//         if (!tokenClaimedByAccount[accountAddress][claimTokenAddress]) {
//             tokenClaimedByAccount[accountAddress][claimTokenAddress] = true;
//             claimedTokensAddressesByAccount[accountAddress].push(
//                 claimTokenAddress
//             );
//         }
//         amountClaimedByTokenByAccount[accountAddress][
//             claimTokenAddress
//         ] += amount;
//     }