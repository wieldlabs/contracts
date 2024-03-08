/////////
// Wield
// https://wield.xyz
// SPDX-License-Identifier: UNLICENSED
/////////

pragma solidity >=0.8.4;

import "./IPriceOracle.sol";

interface IBebRegistryOneStepController {
    function rentPrice(string memory, uint256)
        external
        returns (IPriceOracle.Price memory);

    function available(string memory) external returns (bool);

    function register(
        string calldata,
        address,
        uint256
    ) external payable;

    function renew(string calldata, uint256) external payable;
}
