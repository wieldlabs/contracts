/////////
// Wield
// https://wield.xyz
// SPDX-License-Identifier: AGPL-3.0-or-later
/////////

pragma solidity 0.8.21;

import "@openzeppelin/contracts/access/Ownable.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import "@openzeppelin/contracts/interfaces/IERC1271.sol";
import "@openzeppelin/contracts/utils/Create2.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

interface IIdRegistry {
    /*//////////////////////////////////////////////////////////////
                              CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Defined for compatibility with tools like Etherscan that detect fid
     *         transfers as token transfers. This is intentionally lowercased.
     */
    function name() external view returns (string memory);

    /**
     * @notice Contract version specified in the Farcaster protocol version scheme.
     */
    function VERSION() external view returns (string memory);

    /**
     * @notice EIP-712 typehash for Register signatures.
     */
    function REGISTER_TYPEHASH() external view returns (bytes32);

    /**
     * @notice EIP-712 typehash for Transfer signatures.
     */
    function TRANSFER_TYPEHASH() external view returns (bytes32);

    /**
     * @notice EIP-712 typehash for ChangeRecoveryAddress signatures.
     */
    function CHANGE_RECOVERY_ADDRESS_TYPEHASH() external view returns (bytes32);

    /*//////////////////////////////////////////////////////////////
                                 STORAGE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice The last Farcaster id that was issued.
     */
    function idCounter() external view returns (uint256);

    /**
     * @notice Maps each address to an fid, or zero if it does not own an fid.
     */
    function idOf(address owner) external view returns (uint256 fid);

    /**
     * @notice Maps each fid to an address that can initiate a recovery.
     */
    function recoveryOf(uint256 fid) external view returns (address recovery);

    /*//////////////////////////////////////////////////////////////
                             REGISTRATION LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Register a new Farcaster ID (fid) to the caller. The caller must not have an fid.
     *         The contract must not be in the Registrable (trustedOnly = 0) state.
     *
     * @param recovery Address which can recover the fid. Set to zero to disable recovery.
     *
     * @return fid registered FID.
     */
    function register(address recovery) external returns (uint256 fid);

    /**
     * @notice Register a new Farcaster ID (fid) to any address. A signed message from the address
     *         must be provided which approves both the to and the recovery. The address must not
     *         have an fid. The contract must be in the Registrable (trustedOnly = 0) state.
     *
     * @param to       Address which will own the fid.
     * @param recovery Address which can recover the fid. Set to zero to disable recovery.
     * @param deadline Expiration timestamp of the signature.
     * @param sig      EIP-712 Register signature signed by the to address.
     *
     * @return fid registered FID.
     */
    function registerFor(
        address to,
        address recovery,
        uint256 deadline,
        bytes calldata sig
    ) external returns (uint256 fid);

    /*//////////////////////////////////////////////////////////////
                             TRANSFER LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Transfer the fid owned by this address to another address that does not have an fid.
     *         A signed Transfer message from the destination address must be provided.
     *
     * @param to       The address to transfer the fid to.
     * @param deadline Expiration timestamp of the signature.
     * @param sig      EIP-712 Transfer signature signed by the to address.
     */
    function transfer(address to, uint256 deadline, bytes calldata sig) external;

    /**
     * @notice Transfer the fid owned by the from address to another address that does not
     *         have an fid. Caller must provide two signed Transfer messages: one signed by
     *         the from address and one signed by the to address.
     *
     * @param from         The owner address of the fid to transfer.
     * @param to           The address to transfer the fid to.
     * @param fromDeadline Expiration timestamp of the from signature.
     * @param fromSig      EIP-712 Transfer signature signed by the from address.
     * @param toDeadline   Expiration timestamp of the to signature.
     * @param toSig        EIP-712 Transfer signature signed by the to address.
     */
    function transferFor(
        address from,
        address to,
        uint256 fromDeadline,
        bytes calldata fromSig,
        uint256 toDeadline,
        bytes calldata toSig
    ) external;

    /*//////////////////////////////////////////////////////////////
                             RECOVERY LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Change the recovery address of the fid owned by the caller.
     *
     * @param recovery The address which can recover the fid. Set to 0x0 to disable recovery.
     */
    function changeRecoveryAddress(address recovery) external;

    /**
     * @notice Change the recovery address of fid owned by the owner. Caller must provide an
     *         EIP-712 ChangeRecoveryAddress message signed by the owner.
     *
     * @param owner    Custody address of the fid whose recovery address will be changed.
     * @param recovery The address which can recover the fid. Set to 0x0 to disable recovery.
     * @param deadline Expiration timestamp of the ChangeRecoveryAddress signature.
     * @param sig      EIP-712 ChangeRecoveryAddress message signed by the owner address.
     */
    function changeRecoveryAddressFor(address owner, address recovery, uint256 deadline, bytes calldata sig) external;

    /**
     * @notice Transfer the fid from the from address to the to address. Must be called by the
     *         recovery address. A signed message from the to address must be provided.
     *
     * @param from     The address that currently owns the fid.
     * @param to       The address to transfer the fid to.
     * @param deadline Expiration timestamp of the signature.
     * @param sig      EIP-712 Transfer signature signed by the to address.
     */
    function recover(address from, address to, uint256 deadline, bytes calldata sig) external;

    /**
     * @notice Transfer the fid owned by the from address to another address that does not
     *         have an fid. Caller must provide two signed Transfer messages: one signed by
     *         the recovery address and one signed by the to address.
     *
     * @param from             The owner address of the fid to transfer.
     * @param to               The address to transfer the fid to.
     * @param recoveryDeadline Expiration timestamp of the recovery signature.
     * @param recoverySig      EIP-712 Transfer signature signed by the recovery address.
     * @param toDeadline       Expiration timestamp of the to signature.
     * @param toSig            EIP-712 Transfer signature signed by the to address.
     */
    function recoverFor(
        address from,
        address to,
        uint256 recoveryDeadline,
        bytes calldata recoverySig,
        uint256 toDeadline,
        bytes calldata toSig
    ) external;

    /*//////////////////////////////////////////////////////////////
                                 VIEWS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Verify that a signature was produced by the custody address that owns an fid.
     *
     * @param custodyAddress   The address to check the signature of.
     * @param fid              The fid to check the signature of.
     * @param digest           The digest that was signed.
     * @param sig              The signature to check.
     *
     * @return isValid Whether provided signature is valid.
     */
    function verifyFidSignature(
        address custodyAddress,
        uint256 fid,
        bytes32 digest,
        bytes calldata sig
    ) external view returns (bool isValid);

    /*//////////////////////////////////////////////////////////////
                         PERMISSIONED ACTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Register a new Farcaster ID (fid) to any address. The address must not have an fid.
     *         The contract must be in the Seedable (trustedOnly = 1) state.
     *         Can only be called by the trustedCaller.
     *
     * @param to       The address which will own the fid.
     * @param recovery The address which can recover the fid.
     *
     * @return fid registered FID.
     */
    function trustedRegister(address to, address recovery) external returns (uint256 fid);

    /**
     * @notice Pause registration, transfer, and recovery.
     *         Must be called by the owner.
     */
    function pause() external;

    /**
     * @notice Unpause registration, transfer, and recovery.
     *         Must be called by the owner.
     */
    function unpause() external;

    function nonces(
        address owner
    ) external view returns (uint256);

    function hashTypedDataV4(bytes32 structHash) external view returns (bytes32);
}


contract FidMarketplaceV1Proxy is Ownable, IERC1271 {
    address public immutable factory;
    uint256 public immutable commissionPercentage = 5;  // Commission percentage (0-100)
    IIdRegistry immutable public idRegistry;
    // Minimum fee required to interact with the contract
    uint256 public minFee;
    
    // Owner's signature
    bytes public ownerSignature;

    // Deadline for the transfer
    uint256 public deadline;

    // If listed or not
    bool public isListed = false;

    // Buyer and deposit information
    uint256 private deposit;

    event Listed(uint256 indexed fid, address indexed owner, uint256 amount, uint256 deadline);
    event CancelListed(uint256 indexed fid, address indexed owner, uint256 amount, uint256 deadline);
    event Bought(uint256 indexed fid, address indexed buyer, uint256 amount, address indexed owner);
    
    constructor(
        address _owner, 
        address _factory,
        address _idRegistry
    ) {
        super.transferOwnership(_owner);
        factory = _factory;
        idRegistry = IIdRegistry(_idRegistry);
    }

    modifier onlyFactoryOrOwner() {
        require(msg.sender == factory || msg.sender == owner(), "Only factory or owner can call this function");
        _;
    }

    function _checkOwner() internal view override virtual {
        // transfer from this contract, only allowed when the min deposit is met and the contract is listed
        if (_msgSender() != owner()) {
            require(deposit >= minFee, "Insufficient funds sent");
            require(isListed, "NotListed");
        } else {
            require(owner() == _msgSender(), "Ownable: caller is not the owner");
        }
    }

    // transfer fid to this proxy if it's not already owned by the proxy
    function _transferFidToProxyAndSetRecovery(
        bytes memory ownerProxySignature,
        address to
    ) internal {
        if (idRegistry.idOf(address(this)) == 0) {
            // transfer from owner to this contract
            idRegistry.transferFor(owner(), address(this), deadline, ownerSignature, deadline, ownerProxySignature);
        }
        // set recovery address
        idRegistry.changeRecoveryAddress(to);
    }

    function _cancelListing() internal {
        deposit = 0;
        ownerSignature = "";
        deadline = 0;
        minFee = 0;
        isListed = false;
    }

    function _buy() internal {
        require(msg.value >= minFee, "Insufficient funds sent");
        require(isListed, "NotListed");

        deposit = msg.value;

        uint256 commission = (msg.value * commissionPercentage) / 100;  // Calculate commission

        payable(factory).transfer(commission);  // Send calculated commission

        payable(owner()).transfer(minFee - commission);  // Send funds to owner

        if (msg.value - minFee > 0) {
            payable(msg.sender).transfer(msg.value - minFee);  // Send remaining funds to buyer
        }
    }

    function buy(
        bytes memory ownerProxySignature,
        address to,
        uint256 toDeadline,
        bytes memory toSig
    ) public payable {
        _buy();

        _transferFidToProxyAndSetRecovery(ownerProxySignature, to);

        emit Bought(fid(), msg.sender, msg.value, to);
        // transfer from this contract to the buyer
        idRegistry.transfer(to, toDeadline, toSig);

        _cancelListing();
    }

    // buy but keep the FID in the contract
    function proxyBuy(
        bytes memory ownerProxySignature,
        address to
    ) public payable {
        _buy();

        _transferFidToProxyAndSetRecovery(ownerProxySignature, to);

        emit Bought(fid(), msg.sender, msg.value, address(this));
        // keep the FID in the contract
        super.transferOwnership(to);

        _cancelListing();
    }

    function list(bytes memory _ownerSignature, uint256 _deadline, uint256 _minFee) public onlyFactoryOrOwner {
        ownerSignature = _ownerSignature;
        deadline = _deadline;
        minFee = _minFee;
        isListed = true;
        emit Listed(fid(), msg.sender, minFee, deadline);
    }

    function cancelList() public onlyFactoryOrOwner {
        emit CancelListed(fid(), msg.sender, minFee, deadline);
        _cancelListing();
    }

    function isValidSignature(bytes32 hash, bytes memory signature) public view returns (bytes4 magicValue) {
        bool isSignatureValid = SignatureChecker.isValidSignatureNow(owner(), hash, signature);
        bool hasMinimumDeposit = deposit >= minFee;

        if (isSignatureValid || hasMinimumDeposit) {
            return this.isValidSignature.selector;
        } else {
            return bytes4(0);
        }
    }

    // Current FID that the proxy owns
    function fid() public view returns (uint256 _fid) {
        if (idRegistry.idOf(address(this)) == 0) {
            return idRegistry.idOf(owner());
        } else {
            return idRegistry.idOf(address(this));
        }
    }


    /**
     Owner Admin Functions 
     */
    // Function to withdraw funds
    function withdraw() public onlyOwner {
        // Transfer remaining balance to owner
        payable(owner()).transfer(address(this).balance);
    }

    // in case FID is stuck in the contract, owner can withdraw it
    function withdrawFidFromProxy(bytes memory _ownerSignature, uint256 _deadline) public onlyOwner {
        idRegistry.transfer(owner(), _deadline, _ownerSignature);
    }
}

contract FidMarketplaceV3 is IERC1271, Initializable, UUPSUpgradeable {
    struct Offer {
        uint256 amount;
        bytes signature;
        uint256 deadline;
    }
    struct Listing {
        uint256 minFee;
        bytes ownerSignature;
        uint256 deadline;
        address owner;
    }

    bool private processingBuy;
    address public _owner;
    mapping(uint256 => mapping(address => Offer)) public offers;
    mapping(uint256 => Listing) public listings;
    uint256 public commissionPercentage;
    IERC20 public weth;
    IIdRegistry public idRegistry;
    
    event Listed(uint256 indexed fid, address indexed owner, address indexed proxyContract, uint256 amount, uint256 deadline);
    event OfferMade(uint256 indexed fid, address indexed buyer, uint256 amount, uint256 deadline);
    event OfferCanceled(uint256 indexed fid, address indexed buyer);
    event OfferApproved(address indexed owner, uint256 indexed fid, address indexed buyer, uint256 amount);
    event Bought(uint256 indexed fid, address indexed buyer, uint256 amount, address indexed owner);
    event Canceled(uint256 indexed fid);

    constructor(uint256 version) {
        if (version > 1) {
            _disableInitializers();
        }
    }

    function initialize(address anOwner, uint256 _commissionPercentage, address _wethAddress, address _idRegistry) public initializer {
        _owner = anOwner;
        commissionPercentage = _commissionPercentage;
        weth = IERC20(_wethAddress);
        idRegistry = IIdRegistry(_idRegistry);
        processingBuy = false;
    }

    function _cancelListing(uint256 fid) internal {
        delete listings[fid];
    }

    function _cancelOffer(uint256 fid, address buyerAddress) internal {
        delete offers[fid][buyerAddress];
    }

    function _onlyOwner() internal view {
        require(msg.sender == _owner || msg.sender == address(this), "only owner");
    }

    modifier onlyOwner() {
        _onlyOwner();
        _;
    }

    function owner() public view virtual returns (address) {
        return _owner;
    }

    function _buy(address fidOwner, uint256 minFee) internal {
        require(msg.value >= minFee, "Insufficient funds sent");

        processingBuy = true;

        uint256 commission = (msg.value * commissionPercentage) / 100;  // Calculate commission

        payable(fidOwner).transfer(minFee - commission);  // Send funds to owner

        if (msg.value - minFee > 0) {
            payable(msg.sender).transfer(msg.value - minFee);  // Send remaining funds to buyer
        }
    }

    // transfer fid to this proxy if it's not already owned by the proxy
    function _transferFidToProxyAndSetRecovery(
        address owner,
        uint256 deadline,
        bytes memory ownerSignature,
        address to
    ) internal {
        idRegistry.transferFor(owner, address(this), deadline, ownerSignature, deadline, ownerSignature);
        // set recovery address
        idRegistry.changeRecoveryAddress(to);
    }

    function cancelListing(uint256 fid) public {
        require(listings[fid].owner == msg.sender, "Only the owner can cancel the listing");
        _cancelListing(fid);
        emit Canceled(fid);
    }

    function buy(
        uint256 fid,
        address to,
        uint256 toDeadline,
        bytes memory toSig
    ) public payable {
        require(listings[fid].minFee > 0, "NotListed");
        require(processingBuy == false, "AlreadyProcessing");

        _buy(listings[fid].owner, listings[fid].minFee);

        _transferFidToProxyAndSetRecovery(listings[fid].owner, listings[fid].deadline, listings[fid].ownerSignature, to);

        // transfer from this contract to the buyer
        idRegistry.transfer(to, toDeadline, toSig);

        _cancelListing(fid);

        emit Bought(fid, msg.sender, msg.value, to);

        processingBuy = false;
    }

    function list(address owner, uint256 salt, bytes calldata ownerSignature, uint256 minFee, uint256 deadline) public returns (FidMarketplaceV1Proxy ret) {
        bytes32 saltBytes = bytes32(salt); // Convert salt to bytes32 if needed
        address addr = getAddress(owner, salt);
        uint256 fid = idRegistry.idOf(owner);

        require(verifyListSig(fid, owner, addr, deadline, ownerSignature), "Invalid signature");

        ret = new FidMarketplaceV1Proxy{salt: saltBytes}(owner, address(this), address(idRegistry));
            ret.list(ownerSignature, deadline, minFee);

        emit Listed(fid, owner, address(ret), minFee, deadline);
        
        return ret;
    }

    function listWithoutProxy(bytes calldata ownerSignature, uint256 minFee, uint256 deadline) public {
        uint256 fid = idRegistry.idOf(msg.sender);
        require(verifyListSig(fid, msg.sender, address(this), deadline, ownerSignature), "Invalid signature");

        listings[fid] = Listing({
            minFee: minFee,
            ownerSignature: ownerSignature,
            deadline: deadline,
            owner: msg.sender
        });


        emit Listed(fid, msg.sender, address(this), minFee, deadline);
    }

    function getAddress(address owner, uint256 salt) public view returns (address) {
        bytes memory initData = abi.encode(owner, address(this), idRegistry);  // Initialization data
        bytes32 saltBytes = bytes32(salt);

        return Create2.computeAddress(
            saltBytes, 
            keccak256(
                abi.encodePacked(
                    type(FidMarketplaceV1Proxy).creationCode, 
                    initData
                )
            )
        );
    }

    function getOffer(uint256 fid, address buyer) public view returns (Offer memory) {
        return offers[fid][buyer];
    }

    function offer(uint256 fid, uint256 amount, uint256 deadline, bytes calldata signature) public {
        require(amount > 0, "Amount must be greater than zero");

        offers[fid][msg.sender] = Offer({
            amount: amount,
            signature: signature,
            deadline: deadline
        });

        emit OfferMade(fid, msg.sender, amount, deadline);
    }

    function cancelOffer(uint256 fid) public {
        require(offers[fid][msg.sender].amount > 0, "Amount must be greater than zero");
        _cancelOffer(fid, msg.sender);
        emit OfferCanceled(fid, msg.sender);
    }

    function approveOffer(uint256 fid, address buyer, uint256 deadline, bytes calldata ownerSig) public {
        Offer storage offerToApprove = offers[fid][buyer];
        require(offerToApprove.amount > 0, "No offer to approve");
        require(processingBuy == false, "AlreadyProcessing");
        require(idRegistry.idOf(msg.sender) == fid, "Only the owner can approve the offer");

        processingBuy = true;
        uint256 commission = (offerToApprove.amount * commissionPercentage) / 100;
        weth.transferFrom(buyer, address(this), commission);
        weth.transferFrom(buyer, msg.sender, offerToApprove.amount - commission);

        // this will revert if the msg.sender is not the owner of the FID
        _transferFidToProxyAndSetRecovery(msg.sender, deadline, ownerSig, buyer);

        // transfer from this contract to the buyer
        idRegistry.transfer(buyer, offerToApprove.deadline, offerToApprove.signature);

        _cancelOffer(fid, buyer);

        emit OfferApproved(msg.sender, fid, buyer, offerToApprove.amount);

        processingBuy = false;
    }

    // Function to withdraw funds
    function withdraw() public {
        // Transfer remaining balance to owner
        payable(_owner).transfer(address(this).balance);
    }

    function _authorizeUpgrade(address newImplementation) internal view override onlyOwner {
        (newImplementation);
    }
    
    function changeIdRegistry(address _idRegistry) public onlyOwner {
        idRegistry = IIdRegistry(_idRegistry);
    }

    function changeCommission(uint256 _commissionPercentage) public onlyOwner {
        commissionPercentage = _commissionPercentage;
    }

    function changeOwnership(address anOwner) public onlyOwner {
        _owner = anOwner;
    }

    /** View */
    function verifyListSig(uint256 fid, address signer, address to, uint256 deadline, bytes calldata sig) public view returns (bool isValid) {
        bytes32 digest = idRegistry.hashTypedDataV4(keccak256(abi.encode(idRegistry.TRANSFER_TYPEHASH(), fid, to, idRegistry.nonces(signer), deadline)));
        return idRegistry.verifyFidSignature(
            signer, 
            fid, 
            digest, 
            sig
        );
    }

    function isValidSignature(bytes32 hash, bytes memory signature) public view returns (bytes4 magicValue) {
        bool isSignatureValid = SignatureChecker.isValidSignatureNow(_owner, hash, signature);
        bool hasMinimumDeposit = processingBuy == true;

        if (isSignatureValid || hasMinimumDeposit) {
            return this.isValidSignature.selector;
        } else {
            return bytes4(0);
        }
    }


    receive() external payable {}
}