// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.27;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {IFarTokenV2} from "./interfaces/IFarTokenV2.sol";
import {IIdRegistry} from "./interfaces/IIdRegistry.sol";
import {IKeyGateway} from "./interfaces/IKeyGateway.sol";
import {IKeyRegistry} from "./interfaces/IKeyRegistry.sol";
import {INonfungiblePositionManager} from "./interfaces/INonfungiblePositionManager.sol";
import {IUniswapV3Pool} from "./interfaces/IUniswapV3Pool.sol";
import {ISwapRouter} from "./interfaces/ISwapRouter.sol";
import {IProtocolRewards} from "./interfaces/IProtocolRewards.sol";
import {IWETH} from "./interfaces/IWETH.sol";
import {BondingCurveV2} from "./BondingCurveV2.sol";
import {EIP712} from "../lib/EIP712.sol";

abstract contract Pausable {
    bool private _paused;

    /**
     * @dev Emitted when the pause is triggered.
     */
    event Paused();

    /**
     * @dev Emitted when the pause is lifted.
     */
    event Unpaused();

    /**
     * @dev The operation failed because the contract is paused.
     */
    error EnforcedPause();

    /**
     * @dev The operation failed because the contract is not paused.
     */
    error ExpectedPause();

    /**
     * @dev Initializes the contract in unpaused state.
     */
    constructor() {
        _paused = false;
    }

    /**
     * @dev Modifier to make a function callable only when the contract is not paused.
     *
     * Requirements:
     *
     * - The contract must not be paused.
     */
    modifier whenNotPaused() {
        _requireNotPaused();
        _;
    }

    /**
     * @dev Modifier to make a function callable only when the contract is paused.
     *
     * Requirements:
     *
     * - The contract must be paused.
     */
    modifier whenPaused() {
        _requirePaused();
        _;
    }

    /**
     * @dev Returns true if the contract is paused, and false otherwise.
     */
    function paused() public view virtual returns (bool) {
        return _paused;
    }

    /**
     * @dev Throws if the contract is paused.
     */
    function _requireNotPaused() internal view virtual {
        if (paused()) {
            revert EnforcedPause();
        }
    }

    /**
     * @dev Throws if the contract is not paused.
     */
    function _requirePaused() internal view virtual {
        if (!paused()) {
            revert ExpectedPause();
        }
    }

    /**
     * @dev Triggers stopped state.
     *
     * Requirements:
     *
     * - The contract must not be paused.
     */
    function _pause() internal virtual whenNotPaused {
        _paused = true;
        emit Paused();
    }

    /**
     * @dev Returns to normal state.
     *
     * Requirements:
     *
     * - The contract must be paused.
     */
    function _unpause() internal virtual whenPaused {
        _paused = false;
        emit Unpaused();
    }
}

abstract contract Nonces {
    /**
     * @dev The nonce used for an `account` is not the expected current nonce.
     */
    error InvalidAccountNonce(address account, uint256 currentNonce);

    mapping(address account => uint256) private _nonces;

    /**
     * @dev Returns the next unused nonce for an address.
     */
    function nonces(address owner) public view virtual returns (uint256) {
        return _nonces[owner];
    }

    /**
     * @dev Consumes a nonce.
     *
     * Returns the current value and increments nonce.
     */
    function _useNonce(address owner) internal virtual returns (uint256) {
        // For each account, the nonce has an initial value of 0, can only be incremented by one, and cannot be
        // decremented or reset. This guarantees that the nonce never overflows.
        unchecked {
            // It is important to do x++ and not ++x here.
            return _nonces[owner]++;
        }
    }

    /**
     * @dev Same as {_useNonce} but checking that `nonce` is the next valid for `owner`.
     */
    function _useCheckedNonce(address owner, uint256 nonce) internal virtual {
        uint256 current = _useNonce(owner);
        if (nonce != current) {
            revert InvalidAccountNonce(owner, current);
        }
    }
}

contract FarTokenV2 is IFarTokenV2, Initializable, ERC20Upgradeable, ReentrancyGuardUpgradeable, IERC721Receiver, EIP712, Nonces, Pausable {
    uint256 public constant MAX_TOTAL_SUPPLY = 1_000_000_000e18; // 1B tokens
    uint256 internal constant PRIMARY_MARKET_SUPPLY = 800_000_000e18; // 800M tokens
    uint256 internal constant SECONDARY_MARKET_SUPPLY = 200_000_000e18; // 200M tokens
    uint256 public constant TOTAL_FEE_BPS = 100; // 1%
    uint256 public constant TOKEN_CREATOR_FEE_BPS = 0; // optional
    uint256 public constant PROTOCOL_FEE_BPS = 7500; // optional
    uint256 public constant MAX_PLATFORM_REFERRER_FEE_BPS = 1500; // optional
    uint256 public constant MAX_ORDER_REFERRER_FEE_BPS = 1000; // optional
    uint256 public constant MIN_ORDER_SIZE = 0.0000001 ether;
    uint160 internal constant POOL_SQRT_PRICE_X96_WETH_0 = 400950665883918763141200546267337;
    uint160 internal constant POOL_SQRT_PRICE_X96_TOKEN_0 = 15655546353934715619853339;
    uint24 internal constant LP_FEE = 10_000;
    int24 internal constant LP_TICK_LOWER = -887200;
    int24 internal constant LP_TICK_UPPER = 887200;
    uint256 internal constant MIN_ALLOCATED_SUPPLY = 1_000_000e18; // 0.1% of total supply (1M tokens)
    bytes32 public constant WITHDRAW_FROM_RESERVE_TYPEHASH = keccak256(
        "Withdraw(address to,uint256 amount,uint256 nonce,uint256 deadline)"
    );
    bytes32 public constant ADD_TO_RESERVE_TYPEHASH = keccak256(
        "Add(address from,uint256 amount,uint256 nonce,uint256 deadline)"
    );

    address public immutable WETH;
    address public immutable nonfungiblePositionManager;
    address public immutable swapRouter;
    address public immutable protocolFeeRecipient;
    address public immutable protocolRewards;
    BondingCurveV2 public bondingCurve;
    MarketType public marketType;
    address public platformReferrer;
    address public poolAddress;
    address public tokenCreator;
    address public operator;
    string public tokenURI;
    uint256 public platformReferrerFeeBps;
    uint256 public orderReferrerFeeBps;
    uint256 public allocatedSupply;
    uint256 public reservedSupply;
    uint256 public desiredRaise;
    uint256 public uniswapV3PositionId;

    constructor(
        address _protocolFeeRecipient,
        address _protocolRewards,
        address _weth,
        address _nonfungiblePositionManager,
        address _swapRouter
    ) initializer EIP712("FarToken", "1") {
        if (_protocolFeeRecipient == address(0)) revert AddressZero();
        if (_protocolRewards == address(0)) revert AddressZero();
        if (_weth == address(0)) revert AddressZero();
        if (_nonfungiblePositionManager == address(0)) revert AddressZero();
        if (_swapRouter == address(0)) revert AddressZero();

        protocolFeeRecipient = _protocolFeeRecipient;
        protocolRewards = _protocolRewards;
        WETH = _weth;
        nonfungiblePositionManager = _nonfungiblePositionManager;
        swapRouter = _swapRouter;
    }

    /// @notice Initializes a new Far token
    /// @param _tokenCreator The address of the token creator. 
    /// @param _platformReferrer The address of the platform referrer
    /// @param _bondingCurve The address of the bonding curve module
    /// @param _tokenURI The ERC20z token URI
    /// @param _name The token name
    /// @param _symbol The token symbol
    /// @param _platformReferrerFeeBps The platform referrer fee in BPS
    /// @param _orderReferrerFeeBps The order referrer fee in BPS
    /// @param _allocatedSupply The number of tokens allocated to the bonding curve. The portion allocated to the creator is PRIMARY_MARKET_SUPPLY - allocatedSupply
    /// @param _desiredRaise The desired raise for the bonding curve
    function initialize(
        address _tokenCreator,
        address _operator,
        address _platformReferrer,
        address _bondingCurve,
        string memory _tokenURI,
        string memory _name,
        string memory _symbol,
        uint256 _platformReferrerFeeBps,
        uint256 _orderReferrerFeeBps,
        uint256 _allocatedSupply,
        uint256 _desiredRaise
    ) public payable initializer {
        // Validate the creation parameters
        if (_tokenCreator == address(0)) revert AddressZero();
        if (_bondingCurve == address(0)) revert AddressZero();
        if (_platformReferrer == address(0)) {
            _platformReferrer = protocolFeeRecipient;
        }
        if (_platformReferrerFeeBps > MAX_PLATFORM_REFERRER_FEE_BPS) revert PlatformReferrerFeeTooHigh();
        if (_orderReferrerFeeBps > MAX_ORDER_REFERRER_FEE_BPS) revert OrderReferrerFeeTooHigh();
        if (_allocatedSupply > PRIMARY_MARKET_SUPPLY) revert InvalidAllocatedSupply();
        if (_allocatedSupply < MIN_ALLOCATED_SUPPLY) revert InvalidAllocatedSupply();

        // Initialize base contract state
        __ERC20_init(_name, _symbol);
        __ReentrancyGuard_init();

        // Initialize token and market state
        tokenCreator = _tokenCreator;
        marketType = MarketType.BONDING_CURVE;
        platformReferrer = _platformReferrer;
        tokenURI = _tokenURI;
        bondingCurve = BondingCurveV2(_bondingCurve);
        platformReferrerFeeBps = _platformReferrerFeeBps;
        orderReferrerFeeBps = _orderReferrerFeeBps;
        allocatedSupply = _allocatedSupply;
        desiredRaise = _desiredRaise;
        operator = _operator;
        reservedSupply = PRIMARY_MARKET_SUPPLY - allocatedSupply;

        // Determine the token0, token1, and sqrtPriceX96 values for the Uniswap V3 pool
        address token0 = WETH < address(this) ? WETH : address(this);
        address token1 = WETH < address(this) ? address(this) : WETH;
        uint160 sqrtPriceX96 = token0 == WETH ? POOL_SQRT_PRICE_X96_WETH_0 : POOL_SQRT_PRICE_X96_TOKEN_0;

        // Create and initialize the Uniswap V3 pool
        poolAddress = INonfungiblePositionManager(nonfungiblePositionManager).createAndInitializePoolIfNecessary(
            token0, token1, LP_FEE, sqrtPriceX96
        );

        // Execute the initial buy order if any ETH was sent
        if (msg.value > 0) {
            buy(_tokenCreator, _tokenCreator, address(0), "", MarketType.BONDING_CURVE, 0, 0);
        }
    }

    /// @notice Purchases tokens using ETH, either from the bonding curve or Uniswap V3 pool
    /// @param recipient The address to receive the purchased tokens
    /// @param refundRecipient The address to receive any excess ETH
    /// @param orderReferrer The address of the order referrer
    /// @param comment A comment associated with the buy order
    /// @param expectedMarketType The expected market type (0 = BONDING_CURVE, 1 = UNISWAP_POOL)
    /// @param minOrderSize The minimum tokens to prevent slippage
    /// @param sqrtPriceLimitX96 The price limit for Uniswap V3 pool swaps, ignored if market is bonding curve.
    function buy(
        address recipient,
        address refundRecipient,
        address orderReferrer,
        string memory comment,
        MarketType expectedMarketType,
        uint256 minOrderSize,
        uint160 sqrtPriceLimitX96
    ) public payable nonReentrant returns (uint256) {
        // Ensure the market type is expected
        if (marketType != expectedMarketType) revert InvalidMarketType();

        // Ensure the order size is greater than the minimum order size
        if (msg.value < MIN_ORDER_SIZE) revert EthAmountTooSmall();

        // Ensure the recipient is not the zero address
        if (recipient == address(0)) revert AddressZero();

        // Initialize variables to store the total cost, true order size, fee, refund, and whether the market should graduate
        uint256 totalCost;
        uint256 trueOrderSize;
        uint256 fee;
        uint256 refund;
        bool shouldGraduateMarket;

        if (marketType == MarketType.UNISWAP_POOL) {
            // Calculate the fee
            fee = _calculateFee(msg.value, TOTAL_FEE_BPS);

            // Calculate the remaining ETH
            totalCost = msg.value - fee;

            // Handle the fees
            _disperseFees(fee, orderReferrer);

            // Convert the ETH to WETH and approve the swap router
            IWETH(WETH).deposit{value: totalCost}();
            IWETH(WETH).approve(swapRouter, totalCost);

            // Set up the swap parameters
            ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
                tokenIn: WETH,
                tokenOut: address(this),
                fee: LP_FEE,
                recipient: recipient,
                amountIn: totalCost,
                amountOutMinimum: minOrderSize,
                sqrtPriceLimitX96: sqrtPriceLimitX96
            });

            // Execute the swap
            trueOrderSize = ISwapRouter(swapRouter).exactInputSingle(params);
        }

        if (marketType == MarketType.BONDING_CURVE) {
            // Validate the order data
            (totalCost, trueOrderSize, fee, refund, shouldGraduateMarket) = _validateBondingCurveBuy(minOrderSize);

            // Mint the tokens to the recipient
            _mint(recipient, trueOrderSize);

            // Handle the fees
            _disperseFees(fee, orderReferrer);

            // Refund any excess ETH
            if (refund > 0) {
                (bool success,) = refundRecipient.call{value: refund}("");
                if (!success) revert EthTransferFailed();
            }
        }

        // Start the market if this is the final bonding market buy order.
        if (shouldGraduateMarket) {
            _graduateMarket();
        }

        emit FarTokenBuy(
            msg.sender,
            recipient,
            orderReferrer,
            msg.value,
            fee,
            totalCost,
            trueOrderSize,
            balanceOf(recipient),
            comment,
            totalSupply(),
            marketType
        );

        return trueOrderSize;
    }

    /// @notice Sells tokens for ETH, either to the bonding curve or Uniswap V3 pool
    /// @param tokensToSell The number of tokens to sell
    /// @param recipient The address to receive the ETH payout
    /// @param orderReferrer The address of the order referrer
    /// @param comment A comment associated with the sell order
    /// @param expectedMarketType The expected market type (0 = BONDING_CURVE, 1 = UNISWAP_POOL)
    /// @param minPayoutSize The minimum ETH payout to prevent slippage
    /// @param sqrtPriceLimitX96 The price limit for Uniswap V3 pool swaps, ignored if market is bonding curve
    function sell(
        uint256 tokensToSell,
        address recipient,
        address orderReferrer,
        string memory comment,
        MarketType expectedMarketType,
        uint256 minPayoutSize,
        uint160 sqrtPriceLimitX96
    ) external nonReentrant returns (uint256) {
        // Ensure the market type is expected
        if (marketType != expectedMarketType) revert InvalidMarketType();

        // Ensure the sender has enough liquidity to sell
        if (tokensToSell > balanceOf(msg.sender)) revert InsufficientLiquidity();

        // Ensure the recipient is not the zero address
        if (recipient == address(0)) revert AddressZero();

        // Initialize the true payout size
        uint256 truePayoutSize;

        if (marketType == MarketType.UNISWAP_POOL) {
            truePayoutSize = _handleUniswapSell(tokensToSell, minPayoutSize, sqrtPriceLimitX96);
        }

        if (marketType == MarketType.BONDING_CURVE) {
            truePayoutSize = _handleBondingCurveSell(tokensToSell, minPayoutSize);
        }

        // Calculate the fee
        uint256 fee = _calculateFee(truePayoutSize, TOTAL_FEE_BPS);

        // Calculate the payout after the fee
        uint256 payoutAfterFee = truePayoutSize - fee;

        // Handle the fees
        _disperseFees(fee, orderReferrer);

        // Send the payout to the recipient
        (bool success,) = recipient.call{value: payoutAfterFee}("");
        if (!success) revert EthTransferFailed();

        emit FarTokenSell(
            msg.sender,
            recipient,
            orderReferrer,
            truePayoutSize,
            fee,
            payoutAfterFee,
            tokensToSell,
            balanceOf(recipient),
            comment,
            totalSupply(),
            marketType
        );

        return truePayoutSize;
    }

    /// @notice Burns tokens after the market has graduated to Uniswap V3
    /// @param tokensToBurn The number of tokens to burn
    function burn(uint256 tokensToBurn) external {
        if (marketType == MarketType.BONDING_CURVE) revert MarketNotGraduated();

        _burn(msg.sender, tokensToBurn);
    }

    /// @notice Returns current market type and address
    function state() external view returns (MarketState memory) {
        return MarketState({
            marketType: marketType,
            marketAddress: marketType == MarketType.BONDING_CURVE ? address(this) : poolAddress
        });
    }

    /// @notice The number of tokens that can be bought from a given amount of ETH.
    ///         This will revert if the market has graduated to the Uniswap V3 pool.
    function getEthBuyQuote(uint256 ethOrderSize) public view returns (uint256) {
        if (marketType == MarketType.UNISWAP_POOL) revert MarketAlreadyGraduated();

        return bondingCurve.getEthBuyQuote(totalSupply(), allocatedSupply, ethOrderSize, desiredRaise);
    }

    /// @notice The number of tokens for selling a given amount of ETH.
    ///         This will revert if the market has graduated to the Uniswap V3 pool.
    function getEthSellQuote(uint256 ethOrderSize) public view returns (uint256) {
        if (marketType == MarketType.UNISWAP_POOL) revert MarketAlreadyGraduated();

        return bondingCurve.getEthSellQuote(totalSupply(), allocatedSupply, ethOrderSize, desiredRaise);
    }

    /// @notice The amount of ETH needed to buy a given number of tokens.
    ///         This will revert if the market has graduated to the Uniswap V3 pool.
    function getTokenBuyQuote(uint256 tokenOrderSize) public view returns (uint256) {
        if (marketType == MarketType.UNISWAP_POOL) revert MarketAlreadyGraduated();

        return bondingCurve.getTokenBuyQuote(totalSupply(), allocatedSupply, tokenOrderSize, desiredRaise);
    }

    /// @notice The amount of ETH that can be received for selling a given number of tokens.
    ///         This will revert if the market has graduated to the Uniswap V3 pool.
    function getTokenSellQuote(uint256 tokenOrderSize) public view returns (uint256) {
        if (marketType == MarketType.UNISWAP_POOL) revert MarketAlreadyGraduated();

        return bondingCurve.getTokenSellQuote(totalSupply(), allocatedSupply, tokenOrderSize, desiredRaise);
    }

    /// @notice The current exchange rate of the token if the market has not graduated.
    ///         This will revert if the market has graduated to the Uniswap V3 pool.
    function currentExchangeRate() public view returns (uint256) {
        if (marketType == MarketType.UNISWAP_POOL) revert MarketAlreadyGraduated();

        uint256 remainingTokenLiquidity = balanceOf(address(this));
        uint256 ethBalance = address(this).balance;

        if (ethBalance < 0.01 ether) {
            ethBalance = 0.01 ether;
        }

        return (remainingTokenLiquidity * 1e18) / ethBalance;
    }

    /// @notice Receives ETH and executes a buy order.
    receive() external payable {
        if (msg.sender == WETH) {
            return;
        }

        buy(msg.sender, msg.sender, address(0), "", marketType, 0, 0);
    }

    /// @dev For receiving the Uniswap V3 LP NFT on market graduation.
    function onERC721Received(address, address, uint256, bytes calldata) external view returns (bytes4) {
        if (msg.sender != poolAddress) revert OnlyPool();

        return this.onERC721Received.selector;
    }

    /// @dev No-op to allow a swap on the pool to set the correct initial price, if needed
    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata) external {}

    /// @dev Overrides ERC20's _update function to
    ///      - Prevent transfers to the pool if the market has not graduated.
    ///      - Emit the superset `FarTokenTransfer` event with each ERC20 transfer.
    function _update(address from, address to, uint256 value) internal virtual override {
        if (marketType == MarketType.BONDING_CURVE && to == poolAddress) revert MarketNotGraduated();

        super._update(from, to, value);

        emit FarTokenTransfer(from, to, value, balanceOf(from), balanceOf(to), totalSupply());
    }

    /// @dev Validates a bonding curve buy order and if necessary, recalculates the order data if the size is greater than the remaining supply
    function _validateBondingCurveBuy(uint256 minOrderSize)
        internal
        returns (uint256 totalCost, uint256 trueOrderSize, uint256 fee, uint256 refund, bool startMarket)
    {
        // Set the total cost to the amount of ETH sent
        totalCost = msg.value;

        // Calculate the fee
        fee = _calculateFee(totalCost, TOTAL_FEE_BPS);

        // Calculate the amount of ETH remaining for the order
        uint256 remainingEth = totalCost - fee;

        // Get quote for the number of tokens that can be bought with the amount of ETH remaining
        trueOrderSize = bondingCurve.getEthBuyQuote(totalSupply(), allocatedSupply, remainingEth, desiredRaise);

        // Ensure the order size is greater than the minimum order size
        if (trueOrderSize < minOrderSize) revert SlippageBoundsExceeded();

        // Calculate the maximum number of tokens that can be bought
        uint256 maxRemainingTokens = allocatedSupply - totalSupply();

        // Start the market if the order size equals the number of remaining tokens
        if (trueOrderSize == maxRemainingTokens) {
            startMarket = true;
        }

        // If the order size is greater than the maximum number of remaining tokens:
        if (trueOrderSize > maxRemainingTokens) {
            // Reset the order size to the number of remaining tokens
            trueOrderSize = maxRemainingTokens;

            // Calculate the amount of ETH needed to buy the remaining tokens
            uint256 ethNeeded = bondingCurve.getTokenBuyQuote(totalSupply(), allocatedSupply, trueOrderSize, desiredRaise);

            // Recalculate the fee with the updated order size
            fee = _calculateFee(ethNeeded, TOTAL_FEE_BPS);

            // Recalculate the total cost with the updated order size and fee
            totalCost = ethNeeded + fee;

            // Refund any excess ETH
            if (msg.value > totalCost) {
                refund = msg.value - totalCost;
            }

            startMarket = true;
        }
    }

    /// @dev Handles a bonding curve sell order
    function _handleBondingCurveSell(uint256 tokensToSell, uint256 minPayoutSize) private returns (uint256) {
        // Get quote for the number of ETH that can be received for the number of tokens to sell
        uint256 payout = bondingCurve.getTokenSellQuote(totalSupply(), allocatedSupply, tokensToSell, desiredRaise);

        // Ensure the payout is greater than the minimum payout size
        if (payout < minPayoutSize) revert SlippageBoundsExceeded();

        // Ensure the payout is greater than the minimum order size
        if (payout < MIN_ORDER_SIZE) revert EthAmountTooSmall();

        // Burn the tokens from the seller
        _burn(msg.sender, tokensToSell);

        return payout;
    }

    /// @dev Handles a Uniswap V3 sell order
    function _handleUniswapSell(uint256 tokensToSell, uint256 minPayoutSize, uint160 sqrtPriceLimitX96)
        private
        returns (uint256)
    {
        // Transfer the tokens from the seller to this contract
        transfer(address(this), tokensToSell);

        // Approve the swap router to spend the tokens
        this.approve(swapRouter, tokensToSell);

        // Set up the swap parameters
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: address(this),
            tokenOut: WETH,
            fee: LP_FEE,
            recipient: address(this),
            amountIn: tokensToSell,
            amountOutMinimum: minPayoutSize,
            sqrtPriceLimitX96: sqrtPriceLimitX96
        });

        // Execute the swap
        uint256 payout = ISwapRouter(swapRouter).exactInputSingle(params);

        // Withdraw the ETH from the contract
        IWETH(WETH).withdraw(payout);

        return payout;
    }

    /// @dev Graduates the market to a Uniswap V3 pool.
    function _graduateMarket() internal {
        // Update the market type
        marketType = MarketType.UNISWAP_POOL;

        // Convert the bonding curve's accumulated ETH to WETH
        uint256 ethLiquidity = address(this).balance;
        IWETH(WETH).deposit{value: ethLiquidity}();

        // Mint the secondary market supply to this contract
        _mint(address(this), SECONDARY_MARKET_SUPPLY);

        // Approve the nonfungible position manager to transfer the WETH and tokens
        SafeERC20.safeIncreaseAllowance(IERC20(WETH), address(nonfungiblePositionManager), ethLiquidity);
        SafeERC20.safeIncreaseAllowance(this, address(nonfungiblePositionManager), SECONDARY_MARKET_SUPPLY);

        // Determine the token order
        bool isWethToken0 = address(WETH) < address(this);
        address token0 = isWethToken0 ? WETH : address(this);
        address token1 = isWethToken0 ? address(this) : WETH;
        uint256 amount0 = isWethToken0 ? ethLiquidity : SECONDARY_MARKET_SUPPLY;
        uint256 amount1 = isWethToken0 ? SECONDARY_MARKET_SUPPLY : ethLiquidity;

        // Get the current and desired price of the pool
        uint160 currentSqrtPriceX96 = IUniswapV3Pool(poolAddress).slot0().sqrtPriceX96;
        uint160 desiredSqrtPriceX96 = isWethToken0 ? POOL_SQRT_PRICE_X96_WETH_0 : POOL_SQRT_PRICE_X96_TOKEN_0;

        // If the current price is not the desired price, set the desired price
        if (currentSqrtPriceX96 != desiredSqrtPriceX96) {
            bool swap0To1 = currentSqrtPriceX96 > desiredSqrtPriceX96;
            IUniswapV3Pool(poolAddress).swap(address(this), swap0To1, 100, desiredSqrtPriceX96, "");
        }

        // Set up the liquidity position mint parameters
        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: token0,
            token1: token1,
            fee: LP_FEE,
            tickLower: LP_TICK_LOWER,
            tickUpper: LP_TICK_UPPER,
            amount0Desired: amount0,
            amount1Desired: amount1,
            amount0Min: 0,
            amount1Min: 0,
            recipient: address(this),
            deadline: block.timestamp
        });

        // Mint the liquidity position to this contract. It will be non-transferable and fees will be non-claimable.
        (uint256 positionId,,,) = INonfungiblePositionManager(nonfungiblePositionManager).mint(params);

        uniswapV3PositionId = positionId;

        emit FarTokenMarketGraduated(
            address(this), poolAddress, ethLiquidity, SECONDARY_MARKET_SUPPLY, positionId, marketType
        );
    }

    /// @dev Handles calculating and depositing fees to an escrow protocol rewards contract
    function _disperseFees(uint256 _fee, address _orderReferrer) internal {
        if (_orderReferrer == address(0)) {
            _orderReferrer = protocolFeeRecipient;
        }

        uint256 tokenCreatorFee = _calculateFee(_fee, TOKEN_CREATOR_FEE_BPS);
        uint256 platformReferrerFee = _calculateFee(_fee, platformReferrerFeeBps);
        uint256 orderReferrerFee = _calculateFee(_fee, orderReferrerFeeBps);
        uint256 protocolFee = _calculateFee(_fee, PROTOCOL_FEE_BPS);
        uint256 totalFee = tokenCreatorFee + platformReferrerFee + orderReferrerFee + protocolFee;

        address[] memory recipients = new address[](4);
        uint256[] memory amounts = new uint256[](4);
        bytes4[] memory reasons = new bytes4[](4);

        recipients[0] = tokenCreator;
        amounts[0] = tokenCreatorFee;
        reasons[0] = bytes4(keccak256("FAR_CREATOR_FEE"));

        recipients[1] = platformReferrer;
        amounts[1] = platformReferrerFee;
        reasons[1] = bytes4(keccak256("FAR_PLATFORM_REFERRER_FEE"));

        recipients[2] = _orderReferrer;
        amounts[2] = orderReferrerFee;
        reasons[2] = bytes4(keccak256("FAR_ORDER_REFERRER_FEE"));

        recipients[3] = protocolFeeRecipient;
        amounts[3] = protocolFee;
        reasons[3] = bytes4(keccak256("FAR_PROTOCOL_FEE"));

        IProtocolRewards(protocolRewards).depositBatch{value: totalFee}(recipients, amounts, reasons, "");

        emit FarTokenFees(
            tokenCreator,
            platformReferrer,
            _orderReferrer,
            protocolFeeRecipient,
            tokenCreatorFee,
            platformReferrerFee,
            orderReferrerFee,
            protocolFee
        );
    }

    /// @dev Calculates the fee for a given amount and basis points.
    function _calculateFee(uint256 amount, uint256 bps) internal pure returns (uint256) {
        return (amount * bps) / 10_000;
    }

    function _verifySig(bytes32 digest, address signer, uint256 deadline, bytes memory sig) internal view {
        if (block.timestamp >= deadline) revert SignatureExpired();
        if (!SignatureChecker.isValidSignatureNow(signer, digest, sig)) {
            revert InvalidSignature();
        }
    }

    function pause() external {
        if (msg.sender != tokenCreator) revert InvalidTokenCreator();
        _pause();
    }

    function unpause() external {
        if (msg.sender != tokenCreator) revert InvalidTokenCreator();
        _unpause();
    }

    function setOperator(address _operator) external {
        if (msg.sender != tokenCreator) revert InvalidTokenCreator();
        operator = _operator;
    }

    function withdrawFromReserve(uint256 amount, address to) external whenNotPaused {
        if (marketType == MarketType.BONDING_CURVE) revert MarketNotGraduated();
        if (amount > reservedSupply) revert InvalidAmount();
        if (msg.sender != tokenCreator) revert InvalidTokenCreator();

        _mint(to, amount);
        reservedSupply -= amount;

        emit FarTokenWithdrawFromReserve(to, amount);
    }

    function withdrawFromReserveWithSig(uint256 amount, address to, uint256 deadline, bytes memory signature) external whenNotPaused {
        if (marketType == MarketType.BONDING_CURVE) revert MarketNotGraduated();
        if (amount > reservedSupply) revert InvalidAmount();
        
        _verifySig(
            _hashTypedDataV4(keccak256(abi.encode(WITHDRAW_FROM_RESERVE_TYPEHASH, to, amount, _useNonce(operator), deadline))),
            operator,
            deadline,
            signature
        );
        _mint(to, amount);
        reservedSupply -= amount;

        emit FarTokenWithdrawFromReserve(to, amount);
    }

    function addToReserve(uint256 amount) external {
        if (marketType == MarketType.BONDING_CURVE) revert MarketNotGraduated();
        if (balanceOf(msg.sender) < amount) revert InvalidAmount();

        reservedSupply += amount;
        _burn(msg.sender, amount);

        emit FarTokenAddToReserve(msg.sender, amount);
    }

    function addToReserveWithSig(uint256 amount, address from, uint256 deadline, bytes memory signature) external {
        if (marketType == MarketType.BONDING_CURVE) revert MarketNotGraduated();
        if (balanceOf(from) < amount) revert InvalidAmount();
        
        _verifySig(
            _hashTypedDataV4(keccak256(abi.encode(ADD_TO_RESERVE_TYPEHASH, from, amount, _useNonce(from), deadline))),
            from,
            deadline,
            signature
        );
        reservedSupply += amount;
        _burn(from, amount);

        emit FarTokenAddToReserve(from, amount);
    }

    function collectFees() external {
        if (marketType == MarketType.BONDING_CURVE) revert MarketNotGraduated();
        // Prepare the collect params: collect all available fees
        INonfungiblePositionManager.CollectParams memory collectParams = INonfungiblePositionManager.CollectParams({
            tokenId: uniswapV3PositionId,
            recipient: protocolFeeRecipient,
            amount0Max: type(uint128).max,
            amount1Max: type(uint128).max
        });

        // Call collect on the position manager
        INonfungiblePositionManager(nonfungiblePositionManager).collect(collectParams);
    }
}

// Inspired by the open-source Wow Protocol