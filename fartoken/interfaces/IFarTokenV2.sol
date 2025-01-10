// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.27;

/* 
    !!!         !!!         !!!    
    !!!         !!!         !!!    
    !!!         !!!         !!!    
    !!!         !!!         !!!    
    !!!         !!!         !!!    
    !!!         !!!         !!!    

    FAR         FAR         FAR    
*/
interface IFarTokenV2 {
    /// @notice Thrown when an operation is attempted with a zero address
    error AddressZero();

    /// @notice Thrown when an invalid market type is specified
    error InvalidMarketType();

    /// @notice Thrown when there are insufficient funds for an operation
    error InsufficientFunds();

    /// @notice Thrown when there is insufficient liquidity for a transaction
    error InsufficientLiquidity();

    /// @notice Thrown when the slippage bounds are exceeded during a transaction
    error SlippageBoundsExceeded();

    /// @notice Thrown when the initial order size is too large
    error InitialOrderSizeTooLarge();

    /// @notice Thrown when the ETH amount is too small for a transaction
    error EthAmountTooSmall();

    /// @notice Thrown when an ETH transfer fails
    error EthTransferFailed();

    /// @notice Thrown when an operation is attempted by an entity other than the pool
    error OnlyPool();

    /// @notice Thrown when an operation is attempted by an entity other than WETH
    error OnlyWeth();

    /// @notice Thrown when a market is not yet graduated
    error MarketNotGraduated();

    /// @notice Thrown when a market is already graduated
    error MarketAlreadyGraduated();

    /// @notice Thrown when a platform referrer fee is set to higher than max allowed
    error PlatformReferrerFeeTooHigh();

    /// @notice Thrown when an order referrer fee is set to higher than max allowed
    error OrderReferrerFeeTooHigh();

    /// @notice Thrown when an invalid allocated supply is specified
    error InvalidAllocatedSupply();

    /// @notice Thrown when an invalid token creator is not the owner of the fid
    error InvalidTokenCreator();

    /// @notice Thrown when an invalid amount is specified
    error InvalidAmount();

    /// @notice Thrown when an invalid signature is specified
    error InvalidSignature();

    /// @notice Thrown when a signature deadline is expired
    error SignatureExpired();

    /// @notice Represents the type of market
    enum MarketType {
        BONDING_CURVE,
        UNISWAP_POOL
    }

    /// @notice Represents the state of the market
    struct MarketState {
        MarketType marketType;
        address marketAddress;
    }

    function ADD_TO_RESERVE_TYPEHASH() external view returns (bytes32);

    function WITHDRAW_FROM_RESERVE_TYPEHASH() external view returns (bytes32);

    event FarTokenBuy(
        address indexed buyer,
        address indexed recipient,
        address indexed orderReferrer,
        uint256 totalEth,
        uint256 ethFee,
        uint256 ethSold,
        uint256 tokensBought,
        uint256 buyerTokenBalance,
        string comment,
        uint256 totalSupply,
        MarketType marketType
    );

    event FarTokenSell(
        address indexed seller,
        address indexed recipient,
        address indexed orderReferrer,
        uint256 totalEth,
        uint256 ethFee,
        uint256 ethBought,
        uint256 tokensSold,
        uint256 sellerTokenBalance,
        string comment,
        uint256 totalSupply,
        MarketType marketType
    );

    event FarTokenTransfer(
        address indexed from,
        address indexed to,
        uint256 amount,
        uint256 fromTokenBalance,
        uint256 toTokenBalance,
        uint256 totalSupply
    );

    event FarTokenFees(
        address indexed tokenCreator,
        address indexed platformReferrer,
        address indexed orderReferrer,
        address protocolFeeRecipient,
        uint256 tokenCreatorFee,
        uint256 platformReferrerFee,
        uint256 orderReferrerFee,
        uint256 protocolFee
    );

    event FarTokenMarketGraduated(
        address indexed tokenAddress,
        address indexed poolAddress,
        uint256 totalEthLiquidity,
        uint256 totalTokenLiquidity,
        uint256 lpPositionId,
        MarketType marketType
    );

    event FarTokenWithdrawFromReserve(
        address indexed to,
        uint256 amount
    );

    event FarTokenAddToReserve(
        address indexed from,
        uint256 amount
    );

    function buy(
        address recipient,
        address refundRecipient,
        address orderReferrer,
        string memory comment,
        MarketType expectedMarketType,
        uint256 minOrderSize,
        uint160 sqrtPriceLimitX96
    ) external payable returns (uint256);

    function sell(
        uint256 tokensToSell,
        address recipient,
        address orderReferrer,
        string memory comment,
        MarketType expectedMarketType,
        uint256 minPayoutSize,
        uint160 sqrtPriceLimitX96
    ) external returns (uint256);

    function burn(uint256 tokensToBurn) external;

    function getEthBuyQuote(uint256 amount) external view returns (uint256);

    function getTokenSellQuote(uint256 amount) external view returns (uint256);

    function state() external view returns (MarketState memory);

    function tokenURI() external view returns (string memory);

    function tokenCreator() external view returns (address);

    function platformReferrer() external view returns (address);

    function addToReserve(uint256 amount) external;

    function withdrawFromReserve(uint256 amount, address to) external;

    function withdrawFromReserveWithSig(uint256 amount, address to, uint256 deadline, bytes memory signature) external;
} 