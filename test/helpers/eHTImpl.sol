// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {eHT} from "../../src/eHT.sol";
import {MinHeapMap, Heap} from "sol-heap/MinHeapMap.sol";
import {Node, NodeType} from "sol-heap/lib/NodeType.sol";

contract eHTImpl is eHT {
    using MinHeapMap for Heap;

    constructor(
        uint256 finalDeadline,
        uint256 auctionDeadline,
        uint256 confirmationOpen,
        uint256 confirmationDeadline,
        uint256 feeBps,
        address initialOwner,
        address payable feeRecipient
    ) eHT(finalDeadline, auctionDeadline, confirmationOpen, confirmationDeadline, feeBps, initialOwner, feeRecipient) {}

    function confirm(uint256 tokenId) public {
        _confirm(tokenId);
    }

    function exists(uint256 tokenId) internal view returns (bool) {
        Node node = feeRecord.get(tokenId);
        return (Node.unwrap(node) != 0);
    }

    function setFee(uint32 tokenId, uint160 fee) public {
        if (!exists(tokenId)) {
            feeRecord.insert(tokenId, fee);
        } else {
            feeRecord.update(tokenId, fee);
        }
    }
}
