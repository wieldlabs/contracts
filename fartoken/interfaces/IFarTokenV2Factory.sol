// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.27;

interface IFarTokenV2Factory {
    event FarTokenCreated(
        address indexed factoryAddress,
        address indexed tokenCreator,
        address operator,
        address platformReferrer,
        address protocolFeeRecipient,
        address bondingCurve,
        string tokenURI,
        string name,
        string symbol,
        address tokenAddress,
        address poolAddress,
        uint256 platformReferrerFeeBps,
        uint256 orderReferrerFeeBps,
        uint256 allocatedSupply,
        uint256 desiredRaise
    );

    function deploy(
        address _tokenCreator,
        address _operator,
        address _platformReferrer,
        string memory _tokenURI,
        string memory _name,
        string memory _symbol,
        uint256 _platformReferrerFeeBps,
        uint256 _orderReferrerFeeBps,
        uint256 _allocatedSupply,
        uint256 _desiredRaise
    ) external payable returns (address);
} 