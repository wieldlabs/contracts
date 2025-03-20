// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.27;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {ClubCoinDropV1} from "../ClubCoinDropV1.sol";
import {ClubCoinDropDeployer} from "./ClubCoinDropDeployer.sol";

contract ClubCoinDropFactoryV1 is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    // The deployer contract that actually creates the drop and token pairs
    ClubCoinDropDeployer public deployer;
    
    // Default configurations
    ClubCoinDropV1.DropConfig public defaultConfig;
    
    // Errors
    error AddressZero();
    error InvalidParameter();
    
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }
    
    /**
     * @notice Initializes the contract (replaces constructor)
     * @param _deployer Address of the deployer contract
     */
    function initialize(
        ClubCoinDropDeployer _deployer
    ) public initializer {
        if (address(_deployer) == address(0)) revert AddressZero();
        
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        
        // Set deployer
        deployer = _deployer;
        
        // Set default configurations directly instead of using library
        defaultConfig = ClubCoinDropV1.DropConfig({
            whitelistDuration: 3 days,
            publicMintDuration: 4 days,
            startingPrice: 0.1 ether,
            priceCurveRate: 200, // 2% increase per mint
            maxSupply: 1000,
            maxMintsPerAddress: 5,
            baseURI: "https://build.wield.xyz/clubcoin/drop/metadata/",
            vestingDuration: 730 days, // 2 years
            initialRedemptionRate: 3000 // 30%
        });
    }
    
    /**
     * @notice Creates a new drop with default parameters
     * @param nftName Name of the NFT collection
     * @param nftSymbol Symbol of the NFT collection
     * @param tokenName Name of the token
     * @param tokenSymbol Symbol of the token
     * @return dropAddress Address of the deployed drop contract
     * @return tokenAddress Address of the deployed token contract
     */
    function createDrop(
        string memory nftName,
        string memory nftSymbol,
        string memory tokenName,
        string memory tokenSymbol
    ) external returns (address dropAddress, address tokenAddress) {
        return deployer.createDrop(
            msg.sender,
            nftName,
            nftSymbol,
            tokenName,
            tokenSymbol,
            defaultConfig
        );
    }
    
    /**
     * @notice Creates a new drop with custom parameters
     * @param nftName Name of the NFT collection
     * @param nftSymbol Symbol of the NFT collection
     * @param tokenName Name of the token
     * @param tokenSymbol Symbol of the token
     * @param dropConfig Custom configuration for the drop
     * @return dropAddress Address of the deployed drop contract
     * @return tokenAddress Address of the deployed token contract
     */
    function createDropWithConfig(
        string memory nftName,
        string memory nftSymbol,
        string memory tokenName,
        string memory tokenSymbol,
        ClubCoinDropV1.DropConfig memory dropConfig
    ) external returns (address dropAddress, address tokenAddress) {
        return deployer.createDrop(
            msg.sender,
            nftName,
            nftSymbol,
            tokenName,
            tokenSymbol,
            dropConfig
        );
    }
    
    /**
     * @notice Updates the default parameters
     * @param newConfig The new default configuration values
     */
    function updateDefaultConfig(
        ClubCoinDropV1.DropConfig calldata newConfig
    ) external onlyOwner {        
        // Validate the configuration directly
        if (
            newConfig.whitelistDuration < 1 minutes ||
            newConfig.publicMintDuration < 1 minutes ||
            newConfig.startingPrice == 0 ||
            newConfig.priceCurveRate == 0 ||
            newConfig.maxSupply == 0 ||
            newConfig.maxMintsPerAddress == 0 ||
            newConfig.vestingDuration < 1 minutes ||
            newConfig.initialRedemptionRate >= 10000
        ) revert InvalidParameter();
        
        // Update defaults
        defaultConfig = newConfig;
    }
    
    /**
     * @notice Updates the deployer contract
     * @dev Only the owner can call this function
     * @param newDeployer The new deployer contract
     */
    function updateDeployer(
        ClubCoinDropDeployer newDeployer
    ) external onlyOwner {
        if (address(newDeployer) == address(0)) revert AddressZero();
        deployer = newDeployer;
    }
    
    /**
     * @notice Authorization function for contract upgrades
     * @dev Required by UUPSUpgradeable. Only the owner can upgrade the contract.
     * @param newImplementation Address of the new implementation contract
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {
        // Authorization logic in onlyOwner modifier
    }
}