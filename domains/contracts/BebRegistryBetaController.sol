/////////
// Wield
// https://wield.xyz
// SPDX-License-Identifier: AGPL-3.0-or-later
/////////

pragma solidity >=0.8.4;

import "./BaseRegistrar.sol";
import "./StringUtils.sol";
import "./IBebRegistryBetaController.sol";

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "@openzeppelin/contracts/utils/Address.sol";

/**
 * @dev A registrar controller for registering and renewing names at fixed cost.
 */
contract BebRegistryBetaController is Ownable, IBebRegistryBetaController {
    using StringUtils for *;
    using Address for address;

    uint256 public constant MIN_REGISTRATION_DURATION = 28 days;

    BaseRegistrar immutable base;
    IPriceOracle public immutable prices;
    uint256 public immutable minCommitmentAge;
    uint256 public immutable maxCommitmentAge;

    mapping(bytes32 => uint256) public commitments;

    event NameRegistered(
        string name,
        bytes32 indexed label,
        address indexed owner,
        uint256 duration,
        uint256 baseCost,
        uint256 premium,
        uint256 expires
    );
    event NameRenewed(
        string name,
        bytes32 indexed label,
        uint256 cost,
        uint256 expires
    );

    constructor(
        BaseRegistrar _base,
        IPriceOracle _prices,
        uint256 _minCommitmentAge,
        uint256 _maxCommitmentAge
    ) {
        require(_maxCommitmentAge > _minCommitmentAge);

        base = _base;
        prices = _prices;
        minCommitmentAge = _minCommitmentAge;
        maxCommitmentAge = _maxCommitmentAge;
    }

    function rentPrice(string memory name, uint256 duration)
        public
        view
        override
        returns (IPriceOracle.Price memory price)
    {
        bytes32 label = keccak256(bytes(name));
        return prices.price(name, base.nameExpires(uint256(label)), duration);
    }

    function valid(string memory name) public pure returns (bool) {
        return name.strlen() >= 1;
    }

    function available(string memory name) public view override returns (bool) {
        bytes32 label = keccak256(bytes(name));
        return valid(name) && base.available(uint256(label));
    }

    function makeCommitment(
        string memory name,
        address owner,
        uint256 duration,
        bytes32 secret
    ) public pure override returns (bytes32) {
        bytes32 label = keccak256(bytes(name));
        return
            keccak256(
                abi.encode(
                    label,
                    owner,
                    duration,
                    secret
                )
            );
    }

    function commit(bytes32 commitment) public override {
        require(commitments[commitment] + maxCommitmentAge < block.timestamp);
        commitments[commitment] = block.timestamp;
    }

    function register(
        string calldata name,
        address owner,
        uint256 duration,
        bytes32 secret
    ) public payable override {
        bytes32 label = keccak256(bytes(name));
        IPriceOracle.Price memory price = rentPrice(name, duration);
        require(
            msg.value >= (price.base + price.premium),
            "BebRegistryBetaController: Not enough ether provided"
        );

        _consumeCommitment(
            name,
            duration,
            makeCommitment(
                name,
                owner,
                duration,
                secret
            )
        );

        uint256 tokenId = uint256(label);
        uint256 expires = base.register(tokenId, owner, duration);

        emit NameRegistered(
            name,
            label,
            owner,
            duration,
            price.base,
            price.premium,
            expires
        );

        if (msg.value > (price.base + price.premium)) {
            payable(msg.sender).transfer(
                msg.value - (price.base + price.premium)
            );
        }
    }

    function renew(string calldata name, uint256 duration)
        external
        payable
        override
    {
        bytes32 label = keccak256(bytes(name));
        IPriceOracle.Price memory price = rentPrice(name, duration);
        require(
            msg.value >= (price.base + price.premium),
            "BebRegistryBetaController: Not enough Ether provided for renewal"
        );

        uint256 expires = base.renew(uint256(label), duration);

        if (msg.value > (price.base + price.premium)) {
            payable(msg.sender).transfer(msg.value - (price.base + price.premium));
        }

        emit NameRenewed(name, label, price.base + price.premium, expires);
    }

    function withdraw() public {
        payable(owner()).transfer(address(this).balance);
    }

    /* Internal functions */

    function _consumeCommitment(
        string memory name,
        uint256 duration,
        bytes32 commitment
    ) internal {
        // Require a valid commitment (is old enough and is committed)
        require(
            commitments[commitment] + minCommitmentAge <= block.timestamp,
            "BebRegistryBetaController: Commitment is not valid"
        );

        // If the commitment is too old, or the name is registered, stop
        require(
            commitments[commitment] + maxCommitmentAge > block.timestamp,
            "BebRegistryBetaController: Commitment has expired"
        );
        require(available(name), "BebRegistryBetaController: Name is unavailable");

        delete(commitments[commitment]);

        require(duration >= MIN_REGISTRATION_DURATION);
    }
}
