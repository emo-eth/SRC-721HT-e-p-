// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {HT} from "../../src/HT.sol";
import {MinHeapMap, Heap} from "sol-heap/MinHeapMap.sol";
import {Node, NodeType} from "sol-heap/lib/NodeType.sol";

contract HTImpl is HT {
    using MinHeapMap for Heap;

    constructor(uint256 feeBps, address initialOwner, address payable feeRecipient)
        HT(feeBps, initialOwner, feeRecipient)
    {}

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
