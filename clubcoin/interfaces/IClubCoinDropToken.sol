// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.27;

interface IClubCoinDropToken {
    /**
     * @notice Maximum token supply
     */
    function MAX_SUPPLY() external view returns (uint256);
    
    /**
     * @notice Percentage of tokens allocated to NFT holders
     */
    function TOKEN_NFT_PERCENTAGE() external view returns (uint256);
    
    /**
     * @notice Error thrown when liquidity setup fails verification
     */
    error LiquiditySetupFailed();
    
    /**
     * @notice Error thrown when liquidity is already set up
     */
    error LiquidityAlreadySetup();
    
    /**
     * @notice Mints tokens as a reward for burning NFTs
     * @param recipient The address to receive the tokens
     * @param amount The amount of tokens to mint
     */
    function mintReward(address recipient, uint256 amount) external;
    
    /**
     * @notice Sets up liquidity on Uniswap with ETH and tokens
     * @dev Can only be called by the NFT drop contract
     * @dev Will revert with LiquiditySetupFailed if verification checks fail
     * @dev Will revert with LiquidityAlreadySetup if liquidity is already set up
     */
    function setupLiquidity() external payable;
}