// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.4;

import "./BebRegistryOneStepController.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
    
contract BebRegistryBulkRegister is Ownable {
    BebRegistryOneStepController public controller;

    constructor(address _controllerAddress) {
        controller = BebRegistryOneStepController(_controllerAddress);
    }

    function bulkRegister(
        string[] calldata names,
        address[] calldata owners,
        uint256[] calldata durations
    ) external payable {
        require(
            names.length == owners.length && names.length == durations.length,
            "BebRegistryBulkRegister: Input arrays must have the same length"
        );

        uint256 totalCost = calculateTotalPrice(names, durations);
        require(msg.value >= totalCost, "BebRegistryBulkRegister: Insufficient funds");

        for (uint256 i = 0; i < names.length; i++) {
            IPriceOracle.Price memory price = controller.rentPrice(names[i], durations[i]);
            controller.register{value: price.base + price.premium}(names[i], owners[i], durations[i]);
        }

        // Refund excess payment
        if (msg.value > totalCost) {
            payable(msg.sender).transfer(msg.value - totalCost);
        }
    }

    function bulkRenew(string[] calldata names, uint256[] calldata durations) external payable {
        require(
            names.length == durations.length,
            "BebRegistryBulkRegister: Input arrays must have the same length"
        );

        uint256 totalCost = calculateTotalPrice(names, durations);
        require(msg.value >= totalCost, "BebRegistryBulkRegister: Insufficient funds");

        for (uint256 i = 0; i < names.length; i++) {
            controller.renew{value: controller.rentPrice(names[i], durations[i]).base + controller.rentPrice(names[i], durations[i]).premium}(names[i], durations[i]);
        }

        // Refund excess payment
        if (msg.value > totalCost) {
            payable(msg.sender).transfer(msg.value - totalCost);
        }
    }

    function calculateTotalPrice(string[] calldata names, uint256[] calldata durations) public view returns (uint256) {
        require(names.length == durations.length, "Input arrays must have the same length");
        
        uint256 totalCost = 0;
        uint256 length = names.length;
        
        for (uint256 i = 0; i < length;) {
            IPriceOracle.Price memory price = controller.rentPrice(names[i], durations[i]);
            totalCost += price.base + price.premium;
            
            unchecked {
                ++i;
            }
        }
        
        return totalCost;
    }

    function withdraw() external onlyOwner {
        payable(owner()).transfer(address(this).balance);
    }

    receive() external payable {}
}