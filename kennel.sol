// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract Kennel is ERC721, Ownable, ReentrancyGuard {
    using ECDSA for bytes32;

    struct Collection {
        uint256 startToken;
        uint256 size;
        uint256 claimed;
        bytes32 provenanceHash;
        uint256 presaleStart;
        uint256 publicStart;
        uint256 price;
        mapping(address => bool) purchasedPresales;
        address[] _ppaddrs;
        // sequence (img) id = ((token id - startToken) + sequenceOffset) % size
        uint256 sequenceOffset;
    }

    mapping (string => Collection) collections;
    uint256 public maxId;
    string public baseURI;
    address private signer;
    address payable[] private receivers;
    uint256[] private proportions;

    constructor() ERC721("Kennel", "CKC") {}

    function getProvenanceHash(string calldata cn) external view returns (bytes32) {
       return collections[cn].provenanceHash;
    }

    function getRemaining(string calldata cn) external view returns (uint256) {
        require(collections[cn].size > 0);
        return collections[cn].size - collections[cn].claimed;
    }

    function getSequenceOffset(string calldata cn) external view returns (uint256) {
        return collections[cn].sequenceOffset;
    }

    function setSigner(address newSigner) external onlyOwner {
        signer = newSigner;
    }

    function setPayment(address payable[] calldata newReceivers, uint256[] calldata newProportions) external onlyOwner {
        uint256 nrLen = newReceivers.length;
        uint256 npLen = newProportions.length;
        require(nrLen == npLen+1);
        uint256 sum = 0;
        for (uint256 idx = 0; idx < npLen; ++idx)
            sum += newProportions[idx];
        require(sum <= 1_000_000);
        delete receivers;
        delete proportions;
        for (uint256 idx = 0; idx < npLen; ++idx) {
            receivers.push(newReceivers[idx]);
            proportions.push(newProportions[idx]);
        }
        receivers.push(newReceivers[npLen]);
    }

    function initCollection(string calldata cn, uint256 sz, bytes32 ph, uint256 preStart, uint256 pubStart, uint256 price) external onlyOwner {
        require(collections[cn].size == 0 && sz > 0);
        require(preStart <= pubStart);
        collections[cn].startToken = maxId;
        collections[cn].size = sz;
        collections[cn].provenanceHash = ph;
        collections[cn].presaleStart = preStart;
        collections[cn].publicStart = pubStart;
        collections[cn].price = price;
        maxId += sz;
    }

    function reserve(string calldata cn, address[] calldata resfor) external onlyOwner nonReentrant {
        uint256 rfLen = resfor.length;
        require(rfLen > 0);
        require((collections[cn].size - collections[cn].claimed) >= rfLen);
        uint256 idxBase = collections[cn].startToken + collections[cn].claimed;
        for (uint256 idx = 0; idx < rfLen; ++idx)
            _safeMint(resfor[idx], idxBase + idx);
        collections[cn].claimed += rfLen;
        if (collections[cn].claimed == collections[cn].size)
            completeMint(cn);
    }

    function verify(string memory cn, address sender, bytes memory signature) private view returns(bool) {
        bytes32 hash = keccak256(abi.encodePacked(cn, sender));
        return signer == hash.toEthSignedMessageHash().recover(signature);
    }

    function presaleMint(string calldata cn, bytes memory signature) public payable nonReentrant {
        require(collections[cn].size > collections[cn].claimed);
        require(collections[cn].presaleStart <= block.timestamp);
        require(block.timestamp < collections[cn].publicStart);
        require(verify(cn, msg.sender, signature));
        require(!collections[cn].purchasedPresales[msg.sender]);
        require(msg.value >= collections[cn].price);

        uint256 idx = collections[cn].startToken + collections[cn].claimed;
        _safeMint(msg.sender, idx);
        ++collections[cn].claimed;
        collections[cn].purchasedPresales[msg.sender] = true;
        collections[cn]._ppaddrs.push(msg.sender);
        if (collections[cn].claimed == collections[cn].size)
            completeMint(cn);
    }

    function publicMint(string calldata cn, uint256 amount) public payable nonReentrant {
        require((collections[cn].size - collections[cn].claimed) >= amount);
        require(collections[cn].publicStart <= block.timestamp);
        require(msg.value >= amount*collections[cn].price);
        require(amount == 1 || amount == 2);

        uint256 idxBase = collections[cn].startToken + collections[cn].claimed;
        for (uint256 idx = 0; idx < amount; ++idx)
            _safeMint(msg.sender, idxBase + idx);
        collections[cn].claimed += amount;
        if (collections[cn].claimed == collections[cn].size)
            completeMint(cn);
    }

    function completeMint(string memory cn) private {
        bytes32 rnd = blockhash(block.number-1);
        collections[cn].sequenceOffset = uint256(rnd) % collections[cn].size;
        uint256 len = collections[cn]._ppaddrs.length;
        uint256 idx;
        while (idx < len)
            delete collections[cn].purchasedPresales[collections[cn]._ppaddrs[idx++]];
        delete collections[cn]._ppaddrs;
    }

    function splitPayment() external {
        uint256 balance = address(this).balance;
        uint256 maxIndex = receivers.length-1;
        for (uint256 idx = 0; idx < maxIndex; ++idx) {
            receivers[idx].call{value: (balance*proportions[idx])/1_000_000}("");
        }
        receivers[maxIndex].call{value: address(this).balance}("");
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_exists(tokenId));
        return bytes(baseURI).length > 0 ? string(abi.encodePacked(baseURI, Strings.toString(tokenId))) : "";
    }

    function setBaseURI(string calldata newBase) external onlyOwner {
        baseURI = newBase;
    }
}
