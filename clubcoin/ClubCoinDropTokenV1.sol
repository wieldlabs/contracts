// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.27;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IUniswapV3Factory} from "./interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "./interfaces/IUniswapV3Pool.sol";
import {INonfungiblePositionManager} from "./interfaces/INonfungiblePositionManager.sol";
import {IWETH} from "./interfaces/IWETH.sol";
import {IClubCoinDropToken} from "./interfaces/IClubCoinDropToken.sol";

contract ClubCoinDropTokenV1 is IClubCoinDropToken, Initializable, ERC20Upgradeable, OwnableUpgradeable, ReentrancyGuardUpgradeable, IERC721Receiver {
    using SafeERC20 for IERC20;
    
    // Constants
    uint256 public constant MAX_SUPPLY = 1_000_000e18; // 1M tokens
    uint256 public constant LP_TOKEN_PERCENTAGE = 20; // 20% of tokens go to LP pool
    uint256 public constant TOKEN_NFT_PERCENTAGE = 80; // 80% of tokens allocated to NFT holders
    uint256 public constant MIN_REWARD_AMOUNT = 1e18; // Minimum reward (1 token)
    uint256 public constant MAX_REWARD_AMOUNT = 800_000e18; // Maximum reward (800k tokens, 80% of MAX_SUPPLY)
    uint24 internal constant LP_FEE = 10000; // 1% fee tier for Uniswap V3
    uint160 internal constant POOL_SQRT_PRICE_X96_WETH_0 = 400950665883918763141200546267337;
    uint160 internal constant POOL_SQRT_PRICE_X96_TOKEN_0 = 15655546353934715619853339;
    
    // Contract references
    address public nftDropContract;
    address public weth;
    address public uniswapV3Factory;
    address public uniswapV3Router;
    address public nonfungiblePositionManager;
    
    // State variables
    address public poolAddress;
    bool public liquiditySetup;
    uint256 public totalBurnRewards;
    uint256 public liquidityPositionId;
    
    // Events
    event RewardMinted(address indexed recipient, uint256 amount);
    event LiquiditySetup(address indexed pool, uint256 ethAmount, uint256 tokenAmount);
    event PositionFeesCollected(uint256 indexed positionId, uint256 amount0, uint256 amount1);
    
    // Errors
    error NotDropContract();
    error AddressZero();
    // LiquidityAlreadySetup() is now defined in the interface
    error MaxSupplyExceeded();
    error LiquidityNotSetup();
    
    /**
     * @notice Modifier to ensure only the NFT drop contract can call
     */
    modifier onlyDropContract() {
        if (msg.sender != nftDropContract) revert NotDropContract();
        _;
    }
    
    /**
     * @notice Required implementation of IERC721Receiver for receiving Uniswap V3 position NFTs
     */
    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        return this.onERC721Received.selector;
    }

    /**
     * @notice Initializes the token contract
     * @param _owner The owner of the contract
     * @param _tokenName The name of the token
     * @param _tokenSymbol The symbol of the token
     * @param _nftDropContract The address of the NFT drop contract
     * @param _weth The address of the WETH contract
     * @param _uniswapV3Factory The address of the Uniswap V3 factory
     * @param _uniswapV3Router The address of the Uniswap V3 router
     * @param _nonfungiblePositionManager The address of the Uniswap V3 NonfungiblePositionManager
     */
    function initialize(
        address _owner,
        string memory _tokenName,
        string memory _tokenSymbol,
        address _nftDropContract,
        address _weth,
        address _uniswapV3Factory,
        address _uniswapV3Router,
        address _nonfungiblePositionManager
    ) external initializer {
        if (_owner == address(0)) revert AddressZero();
        if (_nftDropContract == address(0)) revert AddressZero();
        if (_weth == address(0)) revert AddressZero();
        if (_uniswapV3Factory == address(0)) revert AddressZero();
        if (_uniswapV3Router == address(0)) revert AddressZero();
        if (_nonfungiblePositionManager == address(0)) revert AddressZero();
        
        // Initialize base contracts
        __ERC20_init(_tokenName, _tokenSymbol);
        __Ownable_init(_owner);
        __ReentrancyGuard_init();
        
        // Set addresses
        nftDropContract = _nftDropContract;
        weth = _weth;
        uniswapV3Factory = _uniswapV3Factory;
        uniswapV3Router = _uniswapV3Router;
        nonfungiblePositionManager = _nonfungiblePositionManager;
        
        // Initialize state
        liquiditySetup = false;
        totalBurnRewards = 0;
        
        // Create Uniswap V3 pool
        address token0 = address(this) < weth ? address(this) : weth;
        address token1 = address(this) < weth ? weth : address(this);
        
        // Set initial price based on token ordering
        uint160 sqrtPriceX96 = token0 == weth ? 
            POOL_SQRT_PRICE_X96_WETH_0 : POOL_SQRT_PRICE_X96_TOKEN_0; 
        
        // Create and initialize the pool
        poolAddress = INonfungiblePositionManager(nonfungiblePositionManager).createAndInitializePoolIfNecessary(
            token0,
            token1,
            LP_FEE,
            sqrtPriceX96
        );
    }
    
    /**
     * @notice Mints tokens as rewards for burning NFTs
     * @param recipient The address to receive the tokens
     * @param amount The amount of tokens to mint
     */
    function mintReward(address recipient, uint256 amount) external override onlyDropContract nonReentrant {
        if (recipient == address(0)) revert AddressZero();
        
        // Apply guardrails to prevent minting too many or too few tokens
        if (amount < MIN_REWARD_AMOUNT) {
            amount = MIN_REWARD_AMOUNT;
        } else if (amount > MAX_REWARD_AMOUNT) {
            amount = MAX_REWARD_AMOUNT;
        }
        
        // Ensure we don't exceed max supply
        if (totalSupply() + amount > MAX_SUPPLY) revert MaxSupplyExceeded();
        
        // Update rewards counter
        totalBurnRewards += amount;
        
        // Mint tokens to recipient
        _mint(recipient, amount);
        
        emit RewardMinted(recipient, amount);
    }
    
    /**
     * @notice Sets up liquidity on Uniswap with ETH and tokens
     * @dev Can only be called by NFT drop contract
     * @dev Follows checks-effects-interactions pattern to prevent reentrancy
     */
    function setupLiquidity() external payable override onlyDropContract nonReentrant {
        // ===== CHECKS =====
        // Ensure liquidity hasn't been set up yet
        if (liquiditySetup) revert LiquidityAlreadySetup();
        
        // Verify pool address is set
        require(poolAddress != address(0), "Pool address not set");
        
        // Calculate token amount for liquidity (20% of max supply)
        // But ensure we don't exceed MAX_SUPPLY even if some tokens were already minted
        uint256 remainingSupply = MAX_SUPPLY - totalSupply();
        uint256 desiredLiquidityTokens = (MAX_SUPPLY * LP_TOKEN_PERCENTAGE) / 100;
        uint256 tokensForLiquidity = desiredLiquidityTokens <= remainingSupply ? 
                                      desiredLiquidityTokens : 
                                      remainingSupply;
        
        // Verify we have enough tokens to make liquidity setup worthwhile
        require(tokensForLiquidity > 0, "Insufficient remaining supply");
        
        // ===== EFFECTS =====
        // Mark liquidity as set up BEFORE any external calls
        // This prevents reentrancy attacks
        liquiditySetup = true;
        
        // ===== INTERACTIONS =====
        // Mint tokens for liquidity
        _mint(address(this), tokensForLiquidity);
        
        // Convert ETH to WETH
        IWETH(weth).deposit{value: address(this).balance}();
        
        // Determine token order for the pool
        bool isWethToken0 = weth < address(this);
        
        // Get the total ETH amount
        uint256 ethAmount = IERC20(weth).balanceOf(address(this));
        
        // Approve the tokens to the position manager
        IERC20(weth).approve(nonfungiblePositionManager, ethAmount);
        IERC20(address(this)).approve(nonfungiblePositionManager, tokensForLiquidity);
        
        // Define parameters for providing liquidity
        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: isWethToken0 ? weth : address(this),
            token1: isWethToken0 ? address(this) : weth,
            fee: LP_FEE,
            tickLower: -887200,  // Approx price range 0.1x
            tickUpper: 887200,   // Approx price range 10x
            amount0Desired: isWethToken0 ? ethAmount : tokensForLiquidity,
            amount1Desired: isWethToken0 ? tokensForLiquidity : ethAmount,
            amount0Min: 0,
            amount1Min: 0,
            recipient: address(this),
            deadline: block.timestamp + 30 minutes
        });
        
        // Mint the position and get back a tokenId that represents the position
        (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1) = 
            INonfungiblePositionManager(nonfungiblePositionManager).mint(params);
            
        // Keep track of the position ID
        liquidityPositionId = tokenId;
        
        // Verify the liquidity position was created successfully
        // Both the tokenId and the liquidity amount should be non-zero
        if (tokenId == 0 || liquidity == 0) {
            revert LiquiditySetupFailed();
        }
        
        // Verify that tokens were actually transferred (some amount was used)
        if (amount0 == 0 && amount1 == 0) {
            revert LiquiditySetupFailed();
        }
        
        // Additional verification - check that the pool exists and matches our stored address
        // Get the actual pool from the factory to ensure it matches our stored address
        address verifiedPoolAddress = IUniswapV3Factory(uniswapV3Factory).getPool(
            isWethToken0 ? weth : address(this),
            isWethToken0 ? address(this) : weth,
            LP_FEE
        );
        
        // Verify the pool exists and matches our stored pool address
        if (verifiedPoolAddress == address(0) || verifiedPoolAddress != poolAddress) {
            revert LiquiditySetupFailed();
        }
        
        // Verify the pool is initialized by checking its slot0
        try IUniswapV3Pool(poolAddress).slot0() returns (IUniswapV3Pool.Slot0 memory slot) {
            // Verify the price is non-zero
            if (slot.sqrtPriceX96 == 0) {
                revert LiquiditySetupFailed();
            }
        } catch {
            // If we can't call slot0, the pool might not be properly initialized
            revert LiquiditySetupFailed();
        }
        
        emit LiquiditySetup(poolAddress, ethAmount, tokensForLiquidity);
    }
    
    /**
     * @notice Allows the owner to collect Uniswap V3 position fees
     */
    function collectPositionFees() external onlyOwner nonReentrant {
        require(liquidityPositionId > 0, "No liquidity position");
        require(liquiditySetup, "Liquidity not setup");
        
        // Setup the collect parameters
        INonfungiblePositionManager.CollectParams memory params = INonfungiblePositionManager.CollectParams({
            tokenId: liquidityPositionId,
            recipient: owner(), // Send fees directly to owner
            amount0Max: type(uint128).max, // Collect all token0 fees
            amount1Max: type(uint128).max  // Collect all token1 fees
        });
        
        // Collect the fees
        (uint256 amount0, uint256 amount1) = INonfungiblePositionManager(nonfungiblePositionManager).collect(params);
        
        emit PositionFeesCollected(liquidityPositionId, amount0, amount1);
    }
    
    /**
     * @notice Receive function to allow contract to receive ETH
     */
    receive() external payable {
        // This function is needed to receive ETH from the drop contract
    }
}