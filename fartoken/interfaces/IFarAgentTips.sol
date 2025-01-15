// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.27;

interface IFarAgentTips {
    /// @notice Thrown when an operation is attempted with a zero address
    error AddressZero();

    /// @notice Thrown when an invalid token creator attempts an operation
    error InvalidTokenCreator();

    /// @notice Thrown when an invalid signature is specified
    error InvalidSignature();

    /// @notice Thrown when a signature deadline is expired
    error SignatureExpired();

    /// @notice Thrown when an invalid amount is specified
    error InvalidAmount();

    event FarAgentOperatorUpdated(
        address indexed tokenCreator,
        address indexed oldOperator,
        address indexed newOperator
    );

    event FarAgentWithdrawFromReserve(
        address indexed to,
        uint256 amount
    );

    event FarAgentAddToReserve(
        address indexed from,
        uint256 amount
    );

    function WITHDRAW_FROM_RESERVE_TYPEHASH() external view returns (bytes32);
    function ADD_TO_RESERVE_TYPEHASH() external view returns (bytes32);

    function initialize(
        address _tokenCreator,
        address _operator,
        address _tokenAddress
    ) external;

    function pause() external;
    function unpause() external;

    function tokenCreator() external view returns (address);
    function operator() external view returns (address);
    function tokenAddress() external view returns (address);
    function reservedSupply() external view returns (uint256);

    function setOperator(address _operator) external;
    /// @notice withdraws tokens from the reserve to the to address
    /// @dev Requires msg.sender to be the token creator
    /// @param amount The amount of tokens to withdraw
    /// @param to The address to transfer tokens to
    function withdrawFromReserve(uint256 amount, address to) external;
    /// @notice withdraws tokens from the reserve to the to address with a signature
    /// @dev Requires signature to be valid and the operator to be the signer
    /// @param amount The amount of tokens to withdraw
    /// @param to The address to transfer tokens to
    /// @param deadline The deadline for the signature to be valid
    /// @param signature The signature authorizing the transfer
    function withdrawFromReserveWithSig(uint256 amount, address to, uint256 deadline, bytes memory signature) external;
    /// @notice Adds tokens to the reserve from msg.sender
    /// @dev Requires msg.sender to approve this contract to spend their tokens first
    /// @param amount The amount of tokens to add to reserve
    function addToReserve(uint256 amount) external;
    /// @notice Adds tokens to the reserve with a signature
    /// @dev Requires the from address to approve this contract to spend their tokens first
    /// @param amount The amount of tokens to add to reserve
    /// @param from The address to transfer tokens from
    /// @param deadline The deadline for the signature to be valid
    /// @param signature The signature authorizing the transfer
    function addToReserveWithSig(
        uint256 amount, 
        address from, 
        uint256 deadline, 
        bytes memory signature
    ) external;
}