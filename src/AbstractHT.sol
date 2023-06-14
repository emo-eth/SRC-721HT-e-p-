// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {MinHeapMap, Heap} from "sol-heap/MinHeapMap.sol";
import {ERC2981} from "./lib/ERC2981.sol";
import {Node, NodeType} from "sol-heap/lib/NodeType.sol";
import {Ownable} from "solady/auth/Ownable.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

abstract contract AbstractHT is ERC2981, Ownable {
    using MinHeapMap for Heap;

    error InvalidFeeBPS();

    uint256 public immutable FEE_BPS;
    uint256 internal constant BPS = 10_000;
    address payable public immutable FEE_RECIPIENT;
    Heap feeRecord;

    constructor(uint256 feeBps, address initialOwner, address payable feeRecipient) {
        if (feeBps > BPS || feeBps == 0) {
            revert InvalidFeeBPS();
        }
        FEE_BPS = feeBps;
        FEE_RECIPIENT = feeRecipient;
        _initializeOwner(initialOwner);
    }

    function getCurrentFeeAndPrice(uint256 tokenId) public view virtual returns (uint256 fee, uint256 price);

    function getResalePrice(uint256 tokenId) public view virtual returns (uint256);

    function getFeeFromPrice(uint256 price) public view virtual returns (uint256);

    function getPriceFromFee(uint256 fee) public view virtual returns (uint256);

    function royaltyInfo(uint256, uint256 salePrice)
        external
        view
        override
        returns (address receiver, uint256 royaltyAmount)
    {
        return (FEE_RECIPIENT, getFeeFromPrice(salePrice));
    }
}
