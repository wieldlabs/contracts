// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.27;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import {ERC721EnumerableUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {MerkleWhitelist} from "./lib/MerkleWhitelist.sol";
import {IClubCoinDropToken} from "./interfaces/IClubCoinDropToken.sol";

contract ClubCoinDropV1 is Initializable, ERC721EnumerableUpgradeable, OwnableUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {
    using Strings for uint256;

    // Enums
    enum DropPhase {
        SETUP,           // Initial setup phase
        WHITELIST_MINT,  // Whitelist minting phase (days 0-3)
        PUBLIC_MINT,     // Public minting phase (days 3-7)
        DISTRIBUTION     // Distribution phase (post day 7)
    }

    // Struct for NFT metadata and rewards
    struct NFTData {
        uint256 mintPrice;      // Price paid for the NFT
        uint256 mintTimestamp;  // When the NFT was minted
        bool isBurned;          // Whether the NFT has been burned for tokens
        uint256 burnTimestamp;  // When the NFT was burned (if applicable)
    }

    // Struct for the drop configuration
    struct DropConfig {
        uint256 whitelistDuration;       // Duration of whitelist phase (default 3 days)
        uint256 publicMintDuration;      // Duration of public mint phase (default 4 days)
        uint256 startingPrice;           // Starting price for the first NFT
        uint256 priceCurveRate;          // Rate at which price increases (bps, 100 = 1%)
        uint256 maxSupply;               // Maximum number of NFTs that can be minted
        uint256 maxMintsPerAddress;      // Maximum number of NFTs one address can mint
        string baseURI;                  // Base URI for NFT metadata
        uint256 vestingDuration;         // How long the vesting period lasts (default 730 days/2 years)
        uint256 initialRedemptionRate;   // Initial rate of token redemption when burning (bps, 3000 = 30%)
    }
    
    // Constants
    uint256 public constant MAX_BPS = 10000;           // 100% in basis points
    uint256 internal constant FEE_PERCENTAGE = 1500;    // 15% fee
    
    // State variables
    DropPhase public currentPhase;
    uint256 public phaseEndTime;
    uint256 public totalMinted;
    uint256 public totalBurned;
    uint256 public totalProceeds;
    address public clubTokenAddress;
    address public wethAddress;
    address public feeReceiver;
    
    // Drop configuration
    DropConfig public dropConfig;
    
    // Merkle root for whitelist verification
    bytes32 public whitelistMerkleRoot;
    
    // Mappings
    mapping(uint256 => NFTData) public nftData;
    mapping(address => uint256) public addressMintCount;
    
    // Events
    event Minted(address indexed to, uint256 indexed tokenId, uint256 price);
    event PhaseAdvanced(DropPhase newPhase, uint256 endTime);
    event WhitelistMerkleRootUpdated(bytes32 newMerkleRoot);
    event NFTBurned(address indexed owner, uint256 indexed tokenId, uint256 tokenAmount);
    event DropConfigUpdated(DropConfig newConfig);
    event TokenContractSet(address tokenContract);
    event FeeReceiverUpdated(address indexed previousReceiver, address indexed newReceiver);
    event BaseURIUpdated(string newBaseURI);
    event ProceedsWithdrawn(uint256 totalAmount, uint256 lpFeeAmount, address tokenContract);

    // Errors
    error InvalidPhase();
    error PhaseNotEnded();
    error NotWhitelisted();
    error MaxSupplyReached();
    error MaxMintsPerAddressReached();
    error PriceTooLow();
    error AddressZero();
    error NFTAlreadyBurned();
    error NotNFTOwner();
    error ProceedsTooLow();
    error SaleNotEnded();
    error InvalidMerkleProof();
    error InvalidDuration();
    error InvalidPrice();
    error InvalidRate();
    error InvalidMaxSupply();
    error InvalidMaxMints();
    error TokenContractNotSet();
    
    /**
     * @notice Initializes the ClubCoinDrop contract with parameters for the NFT collection
     * @param _owner The owner of the contract
     * @param _nftName The name of the NFT collection
     * @param _nftSymbol The symbol of the NFT collection
     * @param _wethAddress The address of the WETH contract
     * @param _dropConfig The configuration for the drop
     */
    function initialize(
        address _owner,
        string memory _nftName,
        string memory _nftSymbol,
        address _wethAddress,
        DropConfig memory _dropConfig
    ) external initializer {
        if (_owner == address(0)) revert AddressZero();
        if (_wethAddress == address(0)) revert AddressZero();
        
        // Validate drop configuration
        _validateDropConfig(_dropConfig);
        
        // Initialize base contracts
        __ERC721_init(_nftName, _nftSymbol);
        __ERC721Enumerable_init();
        __Ownable_init(_owner);
        __ReentrancyGuard_init();
        __Pausable_init();
        
        // Set state variables
        wethAddress = _wethAddress;
        dropConfig = _dropConfig;
        feeReceiver = _owner; // Default to contract owner
        
        // Set initial phase
        currentPhase = DropPhase.SETUP;
        
        // Start the whitelist phase
        _advanceToWhitelistPhase();
        
        // Emit the configuration event
        emit DropConfigUpdated(_dropConfig);
    }
    
    /**
     * @notice Sets the token contract address
     * @param _tokenAddress The address of the ClubCoinToken contract
     * @dev Can only be called once, either by the factory during initialization or by the owner afterwards
     */
    function setTokenContract(address _tokenAddress) external {
        // Only allow setting if token is not set yet, or if called by owner
        if (clubTokenAddress != address(0) && msg.sender != owner()) {
            revert("Token already set");
        }
        
        // If not called by owner, restrict to initialization phase or factory
        if (msg.sender != owner()) {
            // This allows the factory to set the token during initialization
            // but prevents others from changing it later
            bool isInitializing = currentPhase == DropPhase.SETUP || 
                                 (currentPhase == DropPhase.WHITELIST_MINT && 
                                  block.timestamp < phaseEndTime + 1 minutes);
            require(isInitializing, "Only owner can set token after init");
        }
        
        if (_tokenAddress == address(0)) revert AddressZero();
        
        // Validate the token contract implements the expected interface
        // Just check that it's a contract (has code)
        uint256 codeSize;
        assembly {
            codeSize := extcodesize(_tokenAddress)
        }
        require(codeSize > 0, "Not a contract");
        
        // Store the token address
        clubTokenAddress = _tokenAddress;
        
        // Emit event for tracking
        emit TokenContractSet(_tokenAddress);
    }
    
    /**
     * @notice Sets the Merkle root for whitelist verification
     * @param _merkleRoot The root of the Merkle tree containing whitelisted addresses
     */
    function setWhitelistMerkleRoot(bytes32 _merkleRoot) external onlyOwner {
        // Only allow setting whitelist root during SETUP or WHITELIST_MINT phase
        if (currentPhase != DropPhase.SETUP && currentPhase != DropPhase.WHITELIST_MINT) 
            revert InvalidPhase();
            
        whitelistMerkleRoot = _merkleRoot;
        
        emit WhitelistMerkleRootUpdated(_merkleRoot);
    }
    
    /**
     * @notice Verifies if an address is whitelisted using a Merkle proof
     * @param account The address to verify
     * @param proof The Merkle proof for the address
     * @return Whether the address is whitelisted or not
     */
    function verifyWhitelist(address account, bytes32[] calldata proof) public view returns (bool) {
        return MerkleWhitelist.verifyAddress(account, proof, whitelistMerkleRoot);
    }
    
    /**
     * @notice Updates the drop configuration (only for future phases)
     * @param _dropConfig The new drop configuration
     */
    function updateDropConfig(DropConfig calldata _dropConfig) external onlyOwner {
        // Validate the new configuration
        _validateDropConfig(_dropConfig);
        
        // Update the configuration
        dropConfig = _dropConfig;
        
        emit DropConfigUpdated(_dropConfig);
    }
    
    /**
     * @notice Mints NFTs during the whitelist phase
     * @param merkleProof The Merkle proof proving the sender is whitelisted
     * @param quantity Number of NFTs to mint (default: 1)
     */
    function whitelistMint(bytes32[] calldata merkleProof, uint256 quantity) external payable nonReentrant whenNotPaused {
        // Ensure correct phase
        if (currentPhase != DropPhase.WHITELIST_MINT) revert InvalidPhase();
        
        // Verify whitelist status
        if (!verifyWhitelist(msg.sender, merkleProof)) revert NotWhitelisted();
        
        // Default to 1 if quantity is 0
        if (quantity == 0) {
            quantity = 1;
        }
        
        // Perform the mint
        _mintNFTs(quantity);
        
        // Check if phase should advance
        if (block.timestamp >= phaseEndTime) {
            _advancePhase();
        }
    }
    
    /**
     * @notice Mints NFTs during the public mint phase
     * @param quantity Number of NFTs to mint (default: 1)
     */
    function publicMint(uint256 quantity) external payable nonReentrant whenNotPaused {
        // Ensure correct phase
        if (currentPhase != DropPhase.PUBLIC_MINT) revert InvalidPhase();
        
        // Default to 1 if quantity is 0
        if (quantity == 0) {
            quantity = 1;
        }
        
        // Perform the mint
        _mintNFTs(quantity);
        
        // Check if phase should advance
        if (block.timestamp >= phaseEndTime) {
            _advancePhase();
        }
    }
    
    /**
     * @notice Burns an NFT to receive tokens with vesting rewards
     * @param tokenId The ID of the NFT to burn
     */
    function burnNFTForTokens(uint256 tokenId) external nonReentrant whenNotPaused {
        // Ensure we're in distribution phase
        if (currentPhase != DropPhase.DISTRIBUTION) revert InvalidPhase();
        
        // Ensure token contract is set
        if (clubTokenAddress == address(0)) revert TokenContractNotSet();
        
        // Ensure sender owns the NFT
        if (ownerOf(tokenId) != msg.sender) revert NotNFTOwner();
        
        // Ensure NFT hasn't been burned yet
        if (nftData[tokenId].isBurned) revert NFTAlreadyBurned();
        
        // Calculate token reward based on vesting schedule
        uint256 tokenAmount = calculateTokenReward(tokenId);
        
        // Mark NFT as burned
        nftData[tokenId].isBurned = true;
        nftData[tokenId].burnTimestamp = block.timestamp;
        totalBurned++;
        
        // Burn the NFT
        _burn(tokenId);
        
        // Mint tokens to the sender using the token contract
        IClubCoinDropToken(clubTokenAddress).mintReward(msg.sender, tokenAmount);
        
        emit NFTBurned(msg.sender, tokenId, tokenAmount);
    }
    
    /**
     * @notice Advances the drop to the next phase
     * @dev Can be called by anyone, but only works if the current phase has ended
     */
    function advancePhase() external nonReentrant {
        _advancePhase();
    }
    
    /**
     * @notice Sets the base URI for NFT metadata
     * @param baseURI_ The new base URI
     */
    function setBaseURI(string calldata baseURI_) external onlyOwner {
        dropConfig.baseURI = baseURI_;
        emit BaseURIUpdated(baseURI_);
    }
    
    /**
     * @notice Returns the URI for a given token ID
     * @param tokenId The ID of the token
     * @return The token's metadata URI
     */
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        // This will revert if token doesn't exist
        super.ownerOf(tokenId);
        
        string memory baseURI = dropConfig.baseURI;
        return bytes(baseURI).length > 0 ? string(abi.encodePacked(baseURI, tokenId.toString())) : "";
    }
    
    /**
     * @notice Calculates the current mint price based on the bonding curve
     * @return The price to mint the next NFT
     */
    function getCurrentMintPrice() public view returns (uint256) {
        if (totalMinted == 0) {
            return dropConfig.startingPrice;
        }
        
        // Apply bonding curve: price increases by priceCurveRate for each NFT minted
        return dropConfig.startingPrice + 
               (dropConfig.startingPrice * dropConfig.priceCurveRate * totalMinted) / MAX_BPS;
    }
    
    /**
     * @notice Calculates token reward for burning an NFT based on time since distribution started
     * @dev Gives the same percentage of tokens to all NFT holders with time-based vesting
     * @param tokenId The NFT token ID
     * @return The amount of tokens to reward
     */
    function calculateTokenReward(uint256 tokenId) public view returns (uint256) {
        try this.ownerOf(tokenId) returns (address) {
            // Token exists
            NFTData memory nft = nftData[tokenId];
            
            // Check if it has been burned
            if (nft.isBurned) return 0;
            
            // If token contract is not set, return 0
            if (clubTokenAddress == address(0)) return 0;
            
            // Calculate base token amount from the token contract
            // Total NFT allocation = TOKEN_NFT_PERCENTAGE% of MAX_SUPPLY
            // Each NFT gets an equal share based on the total number of NFTs minted
            uint256 baseTokenAmount;
            try IClubCoinDropToken(clubTokenAddress).MAX_SUPPLY() returns (uint256 maxSupply) {
                try IClubCoinDropToken(clubTokenAddress).TOKEN_NFT_PERCENTAGE() returns (uint256 nftPercentage) {
                    // Calculate tokens per NFT: (maxSupply * nftPercentage / 100) / totalMinted
                    // If no NFTs have been minted yet, use 1 to avoid division by zero
                    uint256 mintCount = totalMinted > 0 ? totalMinted : 1;
                    baseTokenAmount = (maxSupply * nftPercentage / 100) / mintCount;
                } catch {
                    // If TOKEN_NFT_PERCENTAGE not available, fall back to proportional to mint price
                    baseTokenAmount = (nft.mintPrice * 100);
                }
            } catch {
                // If MAX_SUPPLY not available, fall back to proportional to mint price
                baseTokenAmount = (nft.mintPrice * 100);
            }
            
            // Calculate vesting multiplier based on time since distribution started
            uint256 timeElapsed = block.timestamp - phaseEndTime;
            
            // Cap at vesting duration
            if (timeElapsed >= dropConfig.vestingDuration) {
                return baseTokenAmount;
            }
            
            // Linear vesting from initialRedemptionRate to 100%
            uint256 initialRate = dropConfig.initialRedemptionRate;
            uint256 vestingProgress = (timeElapsed * MAX_BPS) / dropConfig.vestingDuration;
            uint256 vestingMultiplier = initialRate + (vestingProgress * (MAX_BPS - initialRate)) / MAX_BPS;
            
            return (baseTokenAmount * vestingMultiplier) / MAX_BPS;
        } catch {
            // Token doesn't exist
            return 0;
        }
    }
    
    /**
     * @notice Returns all proceeds from NFT mints and sets up liquidity
     * @dev Can only be called during DISTRIBUTION phase 
     * @return Total ETH proceeds from the mint
     */
    function withdrawProceedsAndSetupLiquidity() external onlyOwner returns (uint256) {
        if (currentPhase != DropPhase.DISTRIBUTION) revert InvalidPhase();
        
        uint256 contractBalance = address(this).balance;
        if (contractBalance == 0) revert ProceedsTooLow();
        
        // Calculate fee
        uint256 fee = (contractBalance * FEE_PERCENTAGE) / MAX_BPS;
        uint256 remainingBalance = contractBalance - fee;
        
        // Send fee to receiver if fee is non-zero and receiver is set
        if (fee > 0 && feeReceiver != address(0)) {
            (bool feeSuccess, ) = feeReceiver.call{value: fee}("");
            require(feeSuccess, "Fee transfer failed");
        }
        
        // Transfer remaining balance to token contract for liquidity provision
        (bool success, ) = clubTokenAddress.call{value: remainingBalance}("");
        require(success, "Transfer failed");
        
        // Setup liquidity using the token contract
        IClubCoinDropToken(clubTokenAddress).setupLiquidity();
        
        emit ProceedsWithdrawn(contractBalance, fee, clubTokenAddress);
        
        return remainingBalance;
    }
    
    /**
     * @notice Emergency withdrawal function that allows the owner to withdraw all ETH if setupLiquidity fails
     * @dev Can only be called during DISTRIBUTION phase and only by the contract owner
     * @return The amount of ETH withdrawn
     */
    function emergencyWithdraw() external onlyOwner returns (uint256) {
        if (currentPhase != DropPhase.DISTRIBUTION) revert InvalidPhase();
        
        uint256 contractBalance = address(this).balance;
        if (contractBalance == 0) revert ProceedsTooLow();
        
        // Transfer all balance to owner
        (bool success, ) = owner().call{value: contractBalance}("");
        require(success, "Emergency withdrawal failed");
        
        emit ProceedsWithdrawn(contractBalance, 0, address(0));
        
        return contractBalance;
    }
    
    /**
     * @notice Internal function for NFT minting logic
     * @param quantity Number of NFTs to mint
     */
    function _mintNFTs(uint256 quantity) private {
        // Check if max supply would be exceeded
        if (totalMinted + quantity > dropConfig.maxSupply) revert MaxSupplyReached();
        
        // Check if sender has reached max mints per address
        if (addressMintCount[msg.sender] + quantity > dropConfig.maxMintsPerAddress) 
            revert MaxMintsPerAddressReached();
        
        // Calculate total price for all NFTs
        uint256 totalPrice = 0;
        uint256[] memory prices = new uint256[](quantity);
        
        // Calculate price for each NFT using the bonding curve
        for (uint256 i = 0; i < quantity; i++) {
            uint256 currentMinted = totalMinted + i;
            uint256 price = currentMinted == 0 ? 
                dropConfig.startingPrice : 
                dropConfig.startingPrice + (dropConfig.startingPrice * dropConfig.priceCurveRate * currentMinted) / MAX_BPS;
            prices[i] = price;
            totalPrice += price;
        }
        
        // Check if enough ETH was sent
        if (msg.value < totalPrice) revert PriceTooLow();
        
        // Calculate fee
        uint256 fee = (totalPrice * FEE_PERCENTAGE) / MAX_BPS;
        uint256 proceedsAmount = totalPrice - fee;
        
        // Add to total proceeds
        totalProceeds += proceedsAmount;
        
        // Send fee to fee receiver if set
        if (fee > 0 && feeReceiver != address(0)) {
            (bool feeSuccess, ) = feeReceiver.call{value: fee}("");
            require(feeSuccess, "Fee transfer failed");
        } else {
            // If no fee receiver, add fee to proceeds
            totalProceeds += fee;
        }
        
        // Mint each NFT and store data
        for (uint256 i = 0; i < quantity; i++) {
            // Increment counters
            totalMinted++;
            addressMintCount[msg.sender]++;
            
            // Store NFT data
            uint256 tokenId = totalMinted;
            nftData[tokenId] = NFTData({
                mintPrice: prices[i],
                mintTimestamp: block.timestamp,
                isBurned: false,
                burnTimestamp: 0
            });
            
            // Mint the NFT
            _safeMint(msg.sender, tokenId);
            
            // Emit event for each minted NFT
            emit Minted(msg.sender, tokenId, prices[i]);
        }
        
        // Refund excess ETH if any
        if (msg.value > totalPrice) {
            (bool success, ) = msg.sender.call{value: msg.value - totalPrice}("");
            require(success, "Refund failed");
        }
    }
    
    /**
     * @notice Internal function to advance to the next phase
     */
    function _advancePhase() internal {
        // Ensure current phase has ended (except for SETUP)
        if (currentPhase != DropPhase.SETUP && block.timestamp < phaseEndTime) {
            revert PhaseNotEnded();
        }
        
        if (currentPhase == DropPhase.SETUP) {
            _advanceToWhitelistPhase();
        } else if (currentPhase == DropPhase.WHITELIST_MINT) {
            _advanceToPublicMintPhase();
        } else if (currentPhase == DropPhase.PUBLIC_MINT) {
            _advanceToDistributionPhase();
        } else {
            revert InvalidPhase(); // Cannot advance from DISTRIBUTION
        }
    }
    
    /**
     * @notice Advances from SETUP to WHITELIST_MINT phase
     */
    function _advanceToWhitelistPhase() private {
        currentPhase = DropPhase.WHITELIST_MINT;
        phaseEndTime = block.timestamp + dropConfig.whitelistDuration;
        
        emit PhaseAdvanced(DropPhase.WHITELIST_MINT, phaseEndTime);
    }
    
    /**
     * @notice Advances from WHITELIST_MINT to PUBLIC_MINT phase
     */
    function _advanceToPublicMintPhase() private {
        currentPhase = DropPhase.PUBLIC_MINT;
        phaseEndTime = block.timestamp + dropConfig.publicMintDuration;
        
        emit PhaseAdvanced(DropPhase.PUBLIC_MINT, phaseEndTime);
    }
    
    /**
     * @notice Advances from PUBLIC_MINT to DISTRIBUTION phase
     */
    function _advanceToDistributionPhase() private {
        currentPhase = DropPhase.DISTRIBUTION;
        
        // Store the end time for vesting calculations
        phaseEndTime = block.timestamp;
        
        emit PhaseAdvanced(DropPhase.DISTRIBUTION, phaseEndTime);
    }
    
    /**
     * @notice Validates the drop configuration parameters
     * @param _config The drop configuration to validate
     */
    function _validateDropConfig(DropConfig memory _config) internal pure {
        if (_config.whitelistDuration < 1 minutes) revert InvalidDuration();
        if (_config.publicMintDuration < 1 minutes) revert InvalidDuration();
        if (_config.startingPrice == 0) revert InvalidPrice();
        if (_config.priceCurveRate == 0) revert InvalidRate();
        if (_config.maxSupply == 0) revert InvalidMaxSupply();
        if (_config.maxMintsPerAddress == 0) revert InvalidMaxMints();
        if (_config.vestingDuration < 1 minutes) revert InvalidDuration();
        if (_config.initialRedemptionRate >= MAX_BPS) revert InvalidRate();
    }
    
    /**
     * @notice Updates the fee receiver address
     * @param _feeReceiver The new address to receive fees
     */
    function setFeeReceiver(address _feeReceiver) external onlyOwner {
        if (_feeReceiver == address(0)) revert AddressZero();
        address previousReceiver = feeReceiver;
        feeReceiver = _feeReceiver;
        emit FeeReceiverUpdated(previousReceiver, _feeReceiver);
    }
    
    /**
     * @notice Pauses all contract operations
     * @dev Only the owner can call this function
     */
    function pause() external onlyOwner {
        _pause();
    }
    
    /**
     * @notice Unpauses all contract operations
     * @dev Only the owner can call this function
     */
    function unpause() external onlyOwner {
        _unpause();
    }
    
    /**
     * @notice Receive function to allow contract to receive ETH
     */
    receive() external payable {
        // This function is needed to receive ETH, but no action is taken
    }
}