// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.27;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {ClubCoinDropV1} from "../ClubCoinDropV1.sol";
import {ClubCoinDropTokenV1} from "../ClubCoinDropTokenV1.sol";

contract ClubCoinDropDeployer {
    // Events
    event DropCreated(
        address indexed creator,
        address indexed dropContract,
        address indexed tokenContract,
        string nftName,
        string nftSymbol,
        string tokenName,
        string tokenSymbol
    );
    
    // State variables
    address public immutable dropImplementation;
    address public immutable tokenImplementation;
    address public immutable WETH;
    address public immutable uniswapV3Factory;
    address public immutable uniswapV3Router;
    address public immutable nonfungiblePositionManager;
    
    /**
     * @notice Constructor
     * @param _dropImplementation The drop implementation contract
     * @param _tokenImplementation The token implementation contract
     * @param _weth The WETH contract address
     * @param _uniswapV3Factory The Uniswap V3 factory address
     * @param _uniswapV3Router The Uniswap V3 router address
     * @param _nonfungiblePositionManager The Uniswap V3 NonfungiblePositionManager address
     */
    constructor(
        address _dropImplementation,
        address _tokenImplementation,
        address _weth,
        address _uniswapV3Factory,
        address _uniswapV3Router,
        address _nonfungiblePositionManager
    ) {
        require(_dropImplementation != address(0), "Zero address");
        require(_tokenImplementation != address(0), "Zero address");
        require(_weth != address(0), "Zero address");
        require(_uniswapV3Factory != address(0), "Zero address");
        require(_uniswapV3Router != address(0), "Zero address");
        require(_nonfungiblePositionManager != address(0), "Zero address");
        
        dropImplementation = _dropImplementation;
        tokenImplementation = _tokenImplementation;
        WETH = _weth;
        uniswapV3Factory = _uniswapV3Factory;
        uniswapV3Router = _uniswapV3Router;
        nonfungiblePositionManager = _nonfungiblePositionManager;
    }
    
    /**
     * @notice Creates a new drop and token pair with atomic initialization
     * @param owner The owner of the new contracts
     * @param nftName Name of the NFT collection
     * @param nftSymbol Symbol of the NFT collection
     * @param tokenName Name of the token
     * @param tokenSymbol Symbol of the token
     * @param dropConfig Configuration for the drop
     * @return dropAddress Address of the deployed drop contract
     * @return tokenAddress Address of the deployed token contract
     */
    function createDrop(
        address owner,
        string memory nftName,
        string memory nftSymbol,
        string memory tokenName,
        string memory tokenSymbol,
        ClubCoinDropV1.DropConfig memory dropConfig
    ) external returns (address dropAddress, address tokenAddress) {
        // Clone the template contracts
        dropAddress = Clones.clone(dropImplementation);
        tokenAddress = Clones.clone(tokenImplementation);
        
        // Validate the addresses
        require(dropAddress != address(0), "Drop deployment failed");
        require(tokenAddress != address(0), "Token deployment failed");
        
        // Initialize both contracts atomically
        // If any initialization fails, the entire transaction will revert
        
        // Initialize the drop contract
        ClubCoinDropV1(payable(dropAddress)).initialize(
            owner,
            nftName,
            nftSymbol,
            WETH,
            dropConfig
        );
        
        // Initialize the token contract with a reference to the drop contract
        ClubCoinDropTokenV1(payable(tokenAddress)).initialize(
            owner,
            tokenName,
            tokenSymbol,
            dropAddress,
            WETH,
            uniswapV3Factory,
            uniswapV3Router,
            nonfungiblePositionManager
        );
        
        // Complete the linking by setting the token contract in the drop contract
        ClubCoinDropV1(payable(dropAddress)).setTokenContract(tokenAddress);
        
        // Validate contracts are properly linked
        address registeredToken = ClubCoinDropV1(payable(dropAddress)).clubTokenAddress();
        address registeredDrop = ClubCoinDropTokenV1(payable(tokenAddress)).nftDropContract();
        
        require(registeredToken == tokenAddress, "Drop to token link invalid");
        require(registeredDrop == dropAddress, "Token to drop link invalid");
        
        emit DropCreated(
            owner,
            dropAddress,
            tokenAddress,
            nftName,
            nftSymbol,
            tokenName,
            tokenSymbol
        );
        
        return (dropAddress, tokenAddress);
    }
}