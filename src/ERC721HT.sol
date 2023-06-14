// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {AbstractERC721HT} from "./AbstractERC721HT.sol";
import {ERC721} from "solady/tokens/ERC721.sol";
import {ERC2981} from "./lib/ERC2981.sol";
import {MinHeapMap, Heap} from "sol-heap/MinHeapMap.sol";
import {Node, NodeType} from "sol-heap/lib/NodeType.sol";
import {HeapMetadata, HeapMetadataType} from "sol-heap/lib/HeapMetadataType.sol";
import {HT} from "./HT.sol";

contract ERC721HT is AbstractERC721HT, HT {
    constructor(uint256 feeBps, address initialOwner, address payable feeRecipient)
        HT(feeBps, initialOwner, feeRecipient)
    {}

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(AbstractERC721HT, ERC2981)
        returns (bool)
    {
        return AbstractERC721HT.supportsInterface(interfaceId);
    }
}
