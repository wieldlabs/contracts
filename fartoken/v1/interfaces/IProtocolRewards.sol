// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

interface IProtocolRewards {
    event Deposit(address indexed from, address indexed to, bytes4 indexed reason, uint256 amount, string comment);
    event Withdraw(address indexed from, address indexed to, uint256 amount);
    event RewardsDeposit(
        address indexed creator,
        address indexed createReferral,
        address indexed mintReferral,
        address firstMinter,
        address zora,
        address caller,
        uint256 creatorReward,
        uint256 createReferralReward,
        uint256 mintReferralReward,
        uint256 firstMinterReward,
        uint256 zoraReward
    );

    function balanceOf(address account) external view returns (uint256);

    function deposit(address to, bytes4 why, string calldata comment) external payable;

    function depositBatch(
        address[] calldata recipients,
        uint256[] calldata amounts,
        bytes4[] calldata reasons,
        string calldata comment
    ) external payable;
}
