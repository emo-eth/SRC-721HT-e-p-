// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {MinHeapMap, Heap} from "sol-heap/MinHeapMap.sol";
import {ERC2981} from "./lib/ERC2981.sol";
import {Node, NodeType} from "sol-heap/lib/NodeType.sol";
import {Ownable} from "solady/auth/Ownable.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

abstract contract AbstractHarbergerFee is ERC2981, Ownable {
    using MinHeapMap for Heap;

    error InvalidFeeBPS();

    /**
     * @dev The Harberger fee rate for all tokenIds, which determines compulsory resale price.
     */
    uint256 public immutable FEE_BPS;
    /**
     * @dev Denominator for fee calculations.
     */
    uint256 internal constant BPS = 10_000;
    /**
     * @dev The address that receives the fee.
     */
    address payable public immutable FEE_RECIPIENT;

    /**
     * @dev The maximum value (representing fee paid) that can be stored in a node.
     */
    uint256 constant MAX_NODE_VALUE = (1 << 159) - 1;
    /**
     * @dev The context bit that indicates a token is not yet eligible for resale.
     */
    uint256 constant PENDING_CONTEXT = 1 << 159;

    /**
     * @dev Maintain an onchain priority queue of fees paid per tokenId.
     *      In order to maintain the invariant that the top of the heap is always the cheapest token, the following
     *      conditions must be met:
     *      - Price must be a function of the value stored in a Node
     *      - All price curves must be parallel
     *
     *      Peek: O(1)
     *      Pop: O(log(n))
     *      Insert: O(log(n))
     *      Update: O(log(n))
     *      Delete: O(log(n))
     */
    Heap feeRecord;

    constructor(uint256 feeBps, address initialOwner, address payable feeRecipient) {
        // disallow 0 and > 100% fees
        if (feeBps > BPS || feeBps == 0) {
            revert InvalidFeeBPS();
        }
        FEE_BPS = feeBps;
        FEE_RECIPIENT = feeRecipient;
        _initializeOwner(initialOwner);
    }

    /**
     * @dev Set the pending status of a token, and update its position in the priority queue.
     *      This is used to de facto disqualify a token from compulsory resale, by making its resale value
     *      impractically large.
     * @param tokenId The tokenId to set pending status for.
     * @param isPending Whether the token should be marked pending or not.
     */
    function setPendingStatus(uint256 tokenId, bool isPending) internal virtual {
        Node node = feeRecord.get(tokenId);
        uint256 value = node.value();
        if (isPending) {
            value |= PENDING_CONTEXT;
        } else {
            value & MAX_NODE_VALUE;
        }
        feeRecord.update(tokenId, value);
    }

    /**
     * @notice Get the current Harberger fee balance for a token, and its current compulsory resale price.
     * @param tokenId The tokenId to get the fee balance for.
     */
    function getCurrentFeeAndPrice(uint256 tokenId) public view virtual returns (uint256 fee, uint256 price);

    /**
     * @notice Get the current compulsory resale price for a token.
     * @param tokenId The tokenId to get the resale price for.
     */
    function getResalePrice(uint256 tokenId) public view virtual returns (uint256);

    /**
     * @notice Get the Harberger fee that should be paid to set a given resale price.
     * @param price The price to get the fee for.
     */
    function getFeeFromPrice(uint256 price) public view virtual returns (uint256);

    /**
     * @notice Get the compulsory resale price calculated from a given fee amount.
     * @param fee The fee to get the price for.
     */
    function getPriceFromFee(uint256 fee) public view virtual returns (uint256);

    /**
     * See IERC2981
     */
    function royaltyInfo(uint256, uint256 salePrice)
        external
        view
        override
        returns (address receiver, uint256 royaltyAmount)
    {
        return (FEE_RECIPIENT, getFeeFromPrice(salePrice));
    }
}
