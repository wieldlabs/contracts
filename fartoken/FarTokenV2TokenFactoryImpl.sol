// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.27;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {IFarTokenV2Factory} from "./interfaces/IFarTokenV2Factory.sol";
import {FarTokenV2} from "./FarTokenV2.sol";

contract FarTokenV2FactoryImpl is IFarTokenV2Factory, UUPSUpgradeable, ReentrancyGuardUpgradeable, OwnableUpgradeable {
    address public immutable tokenImplementation;
    address public immutable bondingCurve;

    constructor(address _tokenImplementation, address _bondingCurve) {
        tokenImplementation = _tokenImplementation;
        bondingCurve = _bondingCurve;
    }

    /// @notice Initializes the factory proxy contract
    /// @param _owner Address of the contract owner
    /// @dev Can only be called once due to initializer modifier
    function initialize(address _owner) external initializer {
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        __Ownable_init(_owner);
    }

    /// @notice Creates a Far token with bonding curve mechanics that graduates to Uniswap V3
    /// @param _tokenCreator The address of the token creator. Must be the owner of the fid
    /// @param _operator The address of the operator. Must be the owner of the fid
    /// @param _platformReferrer The address of the platform referrer
    /// @param _tokenURI The ERC20z token URI
    /// @param _name The ERC20 token name
    /// @param _symbol The ERC20 token symbol
    /// @param _platformReferrerFeeBps The platform referrer fee in BPS
    /// @param _orderReferrerFeeBps The order referrer fee in BPS
    /// @param _allocatedSupply The number of tokens allocated to the bonding curve. The portion allocated to the creator is PRIMARY_MARKET_SUPPLY - allocatedSupply
    /// @param _desiredRaise The desired raise for the bonding curve
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
    ) external payable nonReentrant returns (address) {
        bytes32 salt = _generateSalt(_tokenCreator, _tokenURI);

        FarTokenV2 token = FarTokenV2(payable(Clones.cloneDeterministic(tokenImplementation, salt)));

        token.initialize{value: msg.value}(_tokenCreator, _operator, _platformReferrer, bondingCurve, _tokenURI, _name, _symbol, _platformReferrerFeeBps, _orderReferrerFeeBps, _allocatedSupply, _desiredRaise);

        emit FarTokenCreated(
            address(this),
            _tokenCreator,
            _operator,
            _platformReferrer,
            token.protocolFeeRecipient(),
            bondingCurve,
            _tokenURI,
            _name,
            _symbol,
            address(token),
            token.poolAddress(),
            _platformReferrerFeeBps,
            _orderReferrerFeeBps,
            _allocatedSupply,
            _desiredRaise
        );

        return address(token);
    }

    /// @dev Generates a unique salt for deterministic deployment
    function _generateSalt(address _tokenCreator, string memory _tokenURI) internal view returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                msg.sender,
                _tokenCreator,
                keccak256(abi.encodePacked(_tokenURI)),
                block.coinbase,
                block.number,
                block.prevrandao,
                block.timestamp,
                tx.gasprice,
                tx.origin
            )
        );
    }

    /// @notice The implementation address of the factory contract
    function implementation() external view returns (address) {
        return ERC1967Utils.getImplementation();
    }

    /// @dev Authorizes an upgrade to a new implementation
    /// @param _newImpl The new implementation address
    function _authorizeUpgrade(address _newImpl) internal override onlyOwner {}
}

// Inspired by the open-source Wow Protocol