// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {HarbergerFee} from "./HarbergerFee.sol";
import {MinHeapMap, Heap} from "sol-heap/MinHeapMap.sol";

/**
 * @title  EphemeralHarbergerFee
 * @author emo.eth
 * @notice An implementation of Harberger fees for "ephemeral goods."
 *
 *         An "ephemeral good" is one that is only valid or relevant within a specific time window.
 *
 *         Categories of ephemeral goods include:
 *         - ticketing: after the event has passed, the ticket is worthless, except as a collectible
 *         - reservations: after the reservation window has passed, the reservation is worthless
 *         - timed redemptions: after the redemption window has passed, a redemption is worthless
 *
 *         Examples of ephemeral goods include:
 *         - concert tickets
 *         - restaurant reservations
 *         - 1:1 consultations
 *         - physical redemptions or preorders with a deadline
 *         - NFT "mint passes" with a deadline
 *
 *         The compulsory sale mechanism of Harberger fees is used to encourage efficient allocation of
 *         ephemeral goods by entering all ephemeral goods without commitments into a compulsory Dutch Auction
 *         as a last resort.
 *
 *         The compulsory sale mechanism for emphemeral goods differs from static or recurring Harberger fees in that
 *         the compulsory resale price curve (CRPC) is a piecewise function, which remains flat until the Dutch Auction
 *         window opens, and then monotonically decreases towards a constant minimum price after that. All tokens
 *         reach the minimum price at the same time, meaning all tokens' CRPCs are non-intersecting.
 *         Due to this fact, it is possible to maintain a sorted onchain orderbook of all tokens in an efficient data
 *         structure by sorting on their paid Harberger fee, since the sorting will always be accurate throughout the
 *         lifecycle of the token.
 *
 *         There are five phases in the lifecycle of an ephemeral good:
 *
 *         - Phase 1: Initial sale/allocation
 *             - Tokens are minted according to whatever mechanism the creator desires.
 *             - example: selling VIP tickets for a concert at a face value
 *         - Phase 2: Resale window
 *             - Voluntary and compulsory secondary sales are conducted during this window. The CRPC during this window
 *               remains static.
 *             - example: market value resale of VIP concert tickets, with mandatory resale fees
 *         - Phase 3: Commitment window
 *             - Owners of tokens may commit to their tokens during this window. Tokens are locked to their owner,
 *               and may not be transferred or resold. The commitment window remains open until the final deadline.
 *             - example: RSVPing to the concert the day before or day of the event, which locks the ticket to the owner.
 *         - Phase 4: Dutch Auction window
 *             - Tokens without a commitment are entered into a compulsory Dutch Auction. The CRPC during
 *               this window is monotonically decreasing towards a minimum price (such as 0), and all tokens will reach
 *               the minimum price at the same time.
 *               The commitment window remains open during the Dutch Auction window in order for new purchasers to exempt
 *               their tokens from the Dutch Auction.
 *             - example: in the hours before the event, and up to an hour into the event, tickets without
 *               confirmations/RSVPs are entered into a Dutch Auction. This is to ensure maximum actual attendance.
 *         - Phase 5: Final Deadline
 *             - The commitment window closes. After this, the token is worthless.
 *             - example: the concert has ended. The ticket token is, at most, memorabilia.
 *
 */
contract EphemeralHarbergerFee is HarbergerFee {
    using MinHeapMap for Heap;

    /// @dev The timestamp after which no token may be committed.
    uint256 public immutable CONFIRMATION_WINDOW_OPEN_TIMESTAMP;
    uint256 public immutable DUTCH_AUCTION_START_TIMESTAMP;
    uint256 public immutable DUTCH_AUCTION_DURATION;
    uint256 public immutable DUTCH_AUCTION_DEADLINE_TIMESTAMP;
    /// @dev The timestamp after which no token may be committed.
    uint256 public immutable FINAL_DEADLINE_TIMESTAMP;

    uint256 public constant CONFIRMED = type(uint152).max;

    error InvalidAuctionDeadline();
    error InvalidConfirmationDeadline();
    error InvalidConfirmationOpen();

    constructor(
        // todo: bitpack these 4 timestamps to reduce calldata?
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
        DUTCH_AUCTION_DEADLINE_TIMESTAMP = auctionDeadline;
        DUTCH_AUCTION_START_TIMESTAMP = confirmationDeadline;
        DUTCH_AUCTION_DURATION = auctionDeadline - confirmationDeadline;
    }

    function _confirm(uint256 tokenId) internal {
        feeRecord.update(tokenId, CONFIRMED);
    }

    function isConfirmed(uint256 id) public view returns (bool) {
        return feeRecord.get(id).value() == CONFIRMED;
    }

    /**
     * @notice Get the price of a token at a given timestamp.
     * @param fee Harberger fee paid for the token
     * @param timestamp timestamp to pass to the price function
     */
    function getAuctionPriceFromFee(uint256 fee, uint256 timestamp) public view virtual returns (uint256) {
        if (timestamp > FINAL_DEADLINE_TIMESTAMP) {
            return type(uint256).max;
        } else if (timestamp >= DUTCH_AUCTION_DEADLINE_TIMESTAMP) {
            return 0;
        }
        uint256 scaleNumerator;
        unchecked {
            scaleNumerator = (DUTCH_AUCTION_DEADLINE_TIMESTAMP - timestamp);
        }
        return (fee * BPS) / (FEE_BPS) * (scaleNumerator / DUTCH_AUCTION_DURATION);
    }

    /**
     * @notice Get the price of a token at the current timestamp.
     * @param fee Harberger fee paid for a token
     */
    function getAuctionPriceFromFee(uint256 fee) public virtual returns (uint256) {
        return getAuctionPriceFromFee(fee, block.timestamp);
    }

    /**
     * @notice Get the price of a token at a given timestamp.
     * @param fee Harberger fee paid for the token
     * @param timestamp timestamp to pass to the price function
     */
    function getPriceFromFee(uint256 fee, uint256 timestamp) public view virtual returns (uint256) {
        if (fee == CONFIRMED) {
            return type(uint256).max;
        }
        if (timestamp < DUTCH_AUCTION_START_TIMESTAMP) {
            return super.getPriceFromFee(fee);
        }
        return getAuctionPriceFromFee(fee, timestamp);
    }

    /**
     * @notice Get the price of a token at the current timestamp.
     * @param fee Harberger fee paid for a token
     */
    function getPriceFromFee(uint256 fee) public view override returns (uint256) {
        return getPriceFromFee(fee, block.timestamp);
    }
}
