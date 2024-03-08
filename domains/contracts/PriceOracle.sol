/////////
// Wield
// https://wield.xyz
// SPDX-License-Identifier: UNLICENSED
//////////////////

pragma solidity >=0.8.4;

import "./IPriceOracle.sol";
import "./StringUtils.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";


// StablePriceOracle sets a price in USD, based on an oracle.
contract PriceOracle is IPriceOracle, Ownable, AccessControl {
    using SafeMath for *;
    using StringUtils for *;

    // Rent in base price units by length, in WEI
    uint256 public basePrice;

    // Rent in premium, in WEI
    uint256 public premiumPriceBase;

    // Granter address
    bytes32 public constant GRANTER_ROLE = keccak256("GRANTER_ROLE");

    constructor(uint256 _basePrice, uint256 _premiumPriceBase, address granter) {
        basePrice = _basePrice;
        premiumPriceBase = _premiumPriceBase;
        _setupRole(GRANTER_ROLE, granter);
    }

    function price(
        string calldata name,
        uint256 expires,
        uint256 duration
    ) external view override returns (IPriceOracle.Price memory) {
        return
            IPriceOracle.Price({
                base: basePrice.mul(duration),
                premium: (_premium(name, expires, duration)).mul(duration)
            });
    }

    /**
     * @dev Returns the pricing premium in wei.
     */
    function premium(
        string calldata name,
        uint256 expires,
        uint256 duration
    ) external view returns (uint256) {
        return _premium(name, expires, duration);
    }

    /**
     * @dev Returns the pricing premium in internal base units.
     */
    function _premium(
        string memory name,
        uint256 expires,
        uint256 duration
    ) internal view virtual returns (uint256) {
        uint256 len = name.strlen();
        require(len >= 1, "PriceOracle: Name must be at least 1 character long");
        if (len >= 10 || hasRole(GRANTER_ROLE, msg.sender)) {
            return 0;
        }
        return (premiumPriceBase == 0) ? 0 : (premiumPriceBase).div(len);
    }

    function toWei(uint256 amount) internal view returns (uint256) {
        uint256 weiAmount = (1e8).mul(amount);
        return weiAmount;
    }

    function changeBasePrice(uint256 newBasePrice) public onlyOwner {
        basePrice = newBasePrice;
    }

    function changePremiumPrice(uint256 newPremiumPriceBase) public onlyOwner {
        premiumPriceBase = newPremiumPriceBase;
    }
}
