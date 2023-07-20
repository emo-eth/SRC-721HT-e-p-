// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {HarbergerFee} from "./HarbergerFee.sol";
import {MinHeapMap, Heap} from "sol-heap/MinHeapMap.sol";

contract HarbergerFeeEphemeral is HarbergerFee {
    using MinHeapMap for Heap;

    uint256 public immutable FINAL_DEADLINE_TIMESTAMP;
    uint256 public immutable AUCTION_DEADLINE_TIMESTAMP;
    uint256 public immutable CONFIRMATION_WINDOW_OPEN_TIMESTAMP;
    uint256 public immutable CONFIRMATION_WINDOW_DEADLINE_TIMESTAMP;
    uint256 public immutable DUTCH_AUCTION_DURATION;
    uint256 public constant CONFIRMED = type(uint152).max;

    error InvalidAuctionDeadline();
    error InvalidConfirmationDeadline();
    error InvalidConfirmationOpen();

    constructor(
        // todo: bitpack these 4 timestamps
        uint256 confirmationOpen,
        uint256 confirmationDeadline,
        uint256 auctionDeadline,
        uint256 finalDeadline,
        uint256 feeBps,
        address initialOwner,
        address payable feeRecipient
    ) HarbergerFee(feeBps, initialOwner, feeRecipient) {
        if (block.timestamp > confirmationOpen) {
            revert InvalidConfirmationOpen();
        }
        if (auctionDeadline > finalDeadline) {
            revert InvalidAuctionDeadline();
        }
        if (confirmationDeadline > auctionDeadline) {
            revert InvalidConfirmationDeadline();
        }
        if (confirmationOpen > confirmationDeadline) {
            revert InvalidConfirmationOpen();
        }

        FINAL_DEADLINE_TIMESTAMP = finalDeadline;
        CONFIRMATION_WINDOW_OPEN_TIMESTAMP = confirmationOpen;
        AUCTION_DEADLINE_TIMESTAMP = auctionDeadline;
        CONFIRMATION_WINDOW_DEADLINE_TIMESTAMP = confirmationDeadline;
        DUTCH_AUCTION_DURATION = auctionDeadline - confirmationDeadline;
    }

    function _confirm(uint256 tokenId) internal {
        feeRecord.update(tokenId, CONFIRMED);
    }

    function isConfirmed(uint256 id) public view returns (bool) {
        return feeRecord.get(id).value() == CONFIRMED;
    }

    function getAuctionPriceFromFee(uint256 fee, uint256 timestamp) public view virtual returns (uint256) {
        if (timestamp > FINAL_DEADLINE_TIMESTAMP) {
            return type(uint256).max;
        } else if (timestamp >= AUCTION_DEADLINE_TIMESTAMP) {
            return 0;
        }
        uint256 scaleNumerator;
        unchecked {
            scaleNumerator = (AUCTION_DEADLINE_TIMESTAMP - timestamp);
        }
        return (fee * BPS) / (FEE_BPS) * (scaleNumerator / DUTCH_AUCTION_DURATION);
    }

    function getAuctionPriceFromFee(uint256 fee) public virtual returns (uint256) {
        return getAuctionPriceFromFee(fee, block.timestamp);
    }

    function getPriceFromFee(uint256 fee, uint256 timestamp) public view virtual returns (uint256) {
        if (fee == CONFIRMED) {
            return type(uint256).max;
        }
        if (timestamp < CONFIRMATION_WINDOW_DEADLINE_TIMESTAMP) {
            return super.getPriceFromFee(fee);
        }
        return getAuctionPriceFromFee(fee, timestamp);
    }

    function getPriceFromFee(uint256 fee) public view override returns (uint256) {
        return getPriceFromFee(fee, block.timestamp);
    }
}
