// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

interface IFarTokenFactory {
    event FarTokenCreated(
        address indexed factoryAddress,
        address indexed tokenCreator,
        address platformReferrer,
        address protocolFeeRecipient,
        address bondingCurve,
        string tokenURI,
        string name,
        string symbol,
        address tokenAddress,
        address poolAddress,
        uint256 platformReferrerFeeBps,
        uint256 orderReferrerFeeBps
    );

    function deploy(
        address _tokenCreator,
        address _platformReferrer,
        string memory _tokenURI,
        string memory _name,
        string memory _symbol,
        uint256 _platformReferrerFeeBps,
        uint256 _orderReferrerFeeBps
    ) external payable returns (address);
} 