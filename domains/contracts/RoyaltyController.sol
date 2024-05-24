/////////
// Wield
// https://wield.xyz
// SPDX-License-Identifier: AGPL-3.0-or-later
//////////////////

pragma solidity >=0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/common/ERC2981.sol";

contract RoyaltyController is Ownable, ERC2981 {
    constructor(address receiver, uint96 feeNumerator) {
        _setDefaultRoyalty(receiver, feeNumerator);
    }

    function setDefaultRoyalty(address receiver, uint96 feeNumerator) public onlyOwner {
        _setDefaultRoyalty(receiver, feeNumerator);
    }

    function setTokenRoyalty(uint256 tokenId, address receiver, uint96 feeNumerator) public onlyOwner {
        _setTokenRoyalty(tokenId, receiver, feeNumerator);
    }
}
