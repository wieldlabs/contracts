// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.27;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {EIP712} from "../lib/EIP712.sol";
import {IFarAgentTips} from "./interfaces/IFarAgentTips.sol";

abstract contract Pausable {
    bool private _paused;

    event Paused();
    event Unpaused();

    error EnforcedPause();
    error ExpectedPause();

    constructor() {
        _paused = false;
    }

    modifier whenNotPaused() {
        _requireNotPaused();
        _;
    }

    modifier whenPaused() {
        _requirePaused();
        _;
    }

    function paused() public view virtual returns (bool) {
        return _paused;
    }

    function _requireNotPaused() internal view virtual {
        if (paused()) {
            revert EnforcedPause();
        }
    }

    function _requirePaused() internal view virtual {
        if (!paused()) {
            revert ExpectedPause();
        }
    }

    function _pause() internal virtual whenNotPaused {
        _paused = true;
        emit Paused();
    }

    function _unpause() internal virtual whenPaused {
        _paused = false;
        emit Unpaused();
    }
}

abstract contract Nonces {
    error InvalidAccountNonce(address account, uint256 currentNonce);

    mapping(address account => uint256) private _nonces;

    function nonces(address owner) public view virtual returns (uint256) {
        return _nonces[owner];
    }

    function _useNonce(address owner) internal virtual returns (uint256) {
        unchecked {
            return _nonces[owner]++;
        }
    }

    function _useCheckedNonce(address owner, uint256 nonce) internal virtual {
        uint256 current = _useNonce(owner);
        if (nonce != current) {
            revert InvalidAccountNonce(owner, current);
        }
    }
}

contract FarAgentTips is IFarAgentTips, Initializable, EIP712, Nonces, Pausable {
    using SafeERC20 for IERC20;

    bytes32 public constant WITHDRAW_FROM_RESERVE_TYPEHASH = keccak256(
        "Withdraw(address to,uint256 amount,uint256 nonce,uint256 deadline)"
    );
    
    bytes32 public constant ADD_TO_RESERVE_TYPEHASH = keccak256(
        "Add(address from,uint256 amount,uint256 nonce,uint256 deadline)"
    );

    address public tokenCreator;
    address public operator;
    address public tokenAddress;
    uint256 public reservedSupply;

    modifier onlyTokenCreator() {
        if (msg.sender != tokenCreator) revert InvalidTokenCreator();
        _;
    }

    constructor() initializer EIP712("FarAgentTips", "1") {}

    function initialize(
        address _tokenCreator,
        address _operator,
        address _tokenAddress
    ) public initializer {
        if (_tokenCreator == address(0)) revert AddressZero();
        if (_operator == address(0)) revert AddressZero();
        if (_tokenAddress == address(0)) revert AddressZero();

        tokenCreator = _tokenCreator;
        operator = _operator;
        tokenAddress = _tokenAddress;
    }

    function _verifySig(bytes32 digest, address signer, uint256 deadline, bytes memory sig) internal view {
        if (block.timestamp >= deadline) revert SignatureExpired();
        if (!SignatureChecker.isValidSignatureNow(signer, digest, sig)) {
            revert InvalidSignature();
        }
    }

    function pause() external onlyTokenCreator {
        _pause();
    }

    function unpause() external onlyTokenCreator {
        _unpause();
    }

    function setOperator(address _operator) external onlyTokenCreator {
        if (_operator == address(0)) revert AddressZero();
        
        address oldOperator = operator;
        operator = _operator;
        
        emit FarAgentOperatorUpdated(tokenCreator, oldOperator, _operator);
    }

    function withdrawFromReserve(uint256 amount, address to) external whenNotPaused onlyTokenCreator {
        if (amount == 0) revert InvalidAmount();
        if (amount > reservedSupply) revert InvalidAmount();

        reservedSupply -= amount;
        IERC20(tokenAddress).safeTransfer(to, amount);

        emit FarAgentWithdrawFromReserve(to, amount);
    }

    function withdrawFromReserveWithSig(uint256 amount, address to, uint256 deadline, bytes memory signature) external whenNotPaused {
        if (amount == 0) revert InvalidAmount();
        if (amount > reservedSupply) revert InvalidAmount();
        
        _verifySig(
            _hashTypedDataV4(keccak256(abi.encode(WITHDRAW_FROM_RESERVE_TYPEHASH, to, amount, _useNonce(to), deadline))),
            operator,
            deadline,
            signature
        );

        reservedSupply -= amount;
        IERC20(tokenAddress).safeTransfer(to, amount);

        emit FarAgentWithdrawFromReserve(to, amount);
    }

    function addToReserve(uint256 amount) external {
        if (amount == 0) revert InvalidAmount();

        IERC20(tokenAddress).safeTransferFrom(msg.sender, address(this), amount);
        reservedSupply += amount;

        emit FarAgentAddToReserve(msg.sender, amount);
    }

    function addToReserveWithSig(uint256 amount, address from, uint256 deadline, bytes memory signature) external {
        if (from == address(0)) revert AddressZero();
        if (amount == 0) revert InvalidAmount();
        
        _verifySig(
            _hashTypedDataV4(keccak256(abi.encode(ADD_TO_RESERVE_TYPEHASH, from, amount, _useNonce(from), deadline))),
            from,
            deadline,
            signature
        );

        IERC20(tokenAddress).safeTransferFrom(from, address(this), amount);
        reservedSupply += amount;

        emit FarAgentAddToReserve(from, amount);
    }
}