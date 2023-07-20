// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {MinHeapMap, Heap} from "sol-heap/MinHeapMap.sol";
import {ERC2981} from "./lib/ERC2981.sol";
import {Node, NodeType} from "sol-heap/lib/NodeType.sol";
import {Ownable} from "solady/auth/Ownable.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {AbstractHarbergerFee} from "./AbstractHarbergerFee.sol";

contract HarbergerFee is AbstractHarbergerFee {
    using MinHeapMap for Heap;

    constructor(uint256 feeBps, address initialOwner, address payable feeRecipient)
        AbstractHarbergerFee(feeBps, initialOwner, feeRecipient)
    {}

    function getCurrentFeeAndPrice(uint256 tokenId) public view override returns (uint256 fee, uint256 price) {
        Node node = feeRecord.get(tokenId);
        fee = node.value() & MAX_NODE_VALUE;
        price = getPriceFromFee(fee);
    }

    function getResalePrice(uint256 tokenId) public view override returns (uint256) {
        // todo: should revert if the node doesn't exist
        (, uint256 price) = getCurrentFeeAndPrice(tokenId);
        return price;
    }

    function getFeeFromPrice(uint256 price) public view virtual override returns (uint256) {
        return (price * FEE_BPS) / BPS;
    }

    function getPriceFromFee(uint256 fee) public view virtual override returns (uint256) {
        return (fee * BPS) / FEE_BPS;
    }
}
