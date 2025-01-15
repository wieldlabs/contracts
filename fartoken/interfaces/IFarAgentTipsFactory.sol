// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.27;

interface IFarAgentTipsFactory {
    event FarAgentTipsCreated(
        address indexed factory,
        address indexed tokenCreator,
        address indexed operator,
        address tokenAddress,
        address agentTips
    );

    /// @notice Deploys a new FarAgentTips contract
    /// @param _tokenCreator The address of the token creator
    /// @param _operator The address of the operator
    /// @param _tokenAddress The address of the token to manage
    /// @return The address of the deployed FarAgentTips contract
    function deploy(
        address _tokenCreator,
        address _operator,
        address _tokenAddress
    ) external returns (address);

    /// @notice The implementation address of the factory contract
    function implementation() external view returns (address);
} 