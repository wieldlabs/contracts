// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.27;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {IFarAgentTipsFactory} from "./interfaces/IFarAgentTipsFactory.sol";
import {FarAgentTips} from "./FarAgentTips.sol";

contract FarAgentTipsFactoryImpl is IFarAgentTipsFactory, UUPSUpgradeable, ReentrancyGuardUpgradeable, OwnableUpgradeable {
    address public immutable tipsImplementation;

    constructor(address _tipsImplementation) {
        if (_tipsImplementation == address(0)) revert("Zero address");
        tipsImplementation = _tipsImplementation;
    }

    /// @notice Initializes the factory proxy contract
    /// @param _owner Address of the contract owner
    /// @dev Can only be called once due to initializer modifier
    function initialize(address _owner) external initializer {
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        __Ownable_init(_owner);
    }

    /// @notice Deploys a new FarAgentTips contract
    /// @param _tokenCreator The address of the token creator
    /// @param _operator The address of the operator
    /// @param _tokenAddress The address of the token to manage
    function deploy(
        address _tokenCreator,
        address _operator,
        address _tokenAddress
    ) external nonReentrant returns (address) {
        bytes32 salt = _generateSalt(_tokenCreator, _tokenAddress);

        FarAgentTips tips = FarAgentTips(Clones.cloneDeterministic(tipsImplementation, salt));

        tips.initialize(
            _tokenCreator,
            _operator,
            _tokenAddress
        );

        emit FarAgentTipsCreated(
            address(this),
            _tokenCreator,
            _operator,
            _tokenAddress,
            address(tips)
        );

        return address(tips);
    }

    /// @dev Generates a unique salt for deterministic deployment
    function _generateSalt(address _tokenCreator, address _tokenAddress) internal view returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                msg.sender,
                _tokenCreator,
                _tokenAddress,
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