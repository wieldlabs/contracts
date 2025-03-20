// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.27;

import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

/**
 * @title MerkleWhitelist
 * @dev Library for handling whitelist verification using Merkle trees
 * This is much more efficient than using a mapping for large whitelists
 */
library MerkleWhitelist {
    /**
     * @notice Verify if an address is whitelisted using a Merkle proof
     * @param account The address to verify
     * @param proof The Merkle proof for the address
     * @param merkleRoot The root of the Merkle tree
     * @return Whether the address is whitelisted or not
     */
    function verifyAddress(
        address account,
        bytes32[] calldata proof,
        bytes32 merkleRoot
    ) internal pure returns (bool) {
        bytes32 leaf = keccak256(abi.encodePacked(account));
        return MerkleProof.verify(proof, merkleRoot, leaf);
    }
}