/////////
// Wield
// https://wield.xyz
// SPDX-License-Identifier: UNLICENSED
/////////

pragma solidity >=0.7.0 <0.9.0;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Beb is ERC1155, Ownable, AccessControl {
    bytes32 public constant GRANTER_ROLE = keccak256("GRANTER_ROLE");
    string public contractUri = "https://bebverse-public.s3.us-west-1.amazonaws.com/contract.json";

    constructor(string memory uri_, address granter) ERC1155(uri_) {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(GRANTER_ROLE, msg.sender);
        _setupRole(GRANTER_ROLE, granter);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC1155, AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function _beforeTokenTransfer(address operator, address from, address to, uint256[] memory ids, uint256[] memory amounts, bytes memory data)
        internal virtual override
    {
        super._beforeTokenTransfer(operator, from, to, ids, amounts, data); // Call parent hook
        require(from == address(0), "BEB: soulbound, non-transferable");
    }

    function setTokenUri(string memory uri)
        public onlyRole(DEFAULT_ADMIN_ROLE)
    {
        super._setURI(uri); // Call parent hook
    }
    function setContractUri(string memory uri)
        public onlyRole(DEFAULT_ADMIN_ROLE)
    {
        contractUri = uri;
    }

    function grantToken(address to, uint256 id, uint256 amount, bytes memory data)
        public onlyRole(GRANTER_ROLE)
    {
        super._mint(to,id,amount,data);
    }

    function grantTokens(address to, uint256[] memory ids, uint256[] memory amounts, bytes memory data)
        public onlyRole(GRANTER_ROLE)
    {
        super._mintBatch(to,ids,amounts,data);
    }

    function contractURI() public view returns (string memory) {
        return contractUri;
    }
}
