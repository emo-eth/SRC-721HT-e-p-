// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {ContractOffererInterface, IERC165} from "seaport-types/interfaces/ContractOffererInterface.sol";
import {AbstractERC721HF} from "./AbstractERC721HF.sol";
import {SpentItem, ReceivedItem, Schema} from "seaport-types/lib/ConsiderationStructs.sol";
import {ItemType} from "seaport-types/lib/ConsiderationEnums.sol";
import {MinHeapMap, Heap} from "sol-heap/MinHeapMap.sol";
import {Node, NodeType} from "sol-heap/lib/NodeType.sol";

abstract contract AbstractSRC721HF is AbstractERC721HF, ContractOffererInterface {
    using MinHeapMap for Heap;

    /// @dev Used if the caller is not the Seaport contract.
    error OnlySeaport();

    /// @dev Used if the token has exceeded the number of free transfers allowed.
    error TokenExceededFreeTransfers();

    /// @dev The address of the Seaport contract, which is the only contract that can call certain functions.
    address immutable SEAPORT;

    /**
     * @dev Since a token may be included in multiple orders, and the FeeRecord is updated before any token transfers
     *      occur, the contract must store the last fee payer for each token. This is used to route payments to the
     *      previous fee payer.
     *      When the stored address is the null address, the owner of the token should be used used.
     *
     */
    mapping(uint32 id => address lastFeePayer) internal lastFeePayers;

    constructor(address seaport) {
        SEAPORT = seaport;
    }

    /**
     * @dev Generates an order with the specified minimum and maximum spent
     *      items, and optional context (supplied as extraData).
     *
     * @param minimumReceived The minimum items that the caller is willing to
     *                        receive.
     * @param maximumSpent    The maximum items the caller is willing to spend.
     *
     * @return newMinimumReceived  A tuple containing the offer items.
     * @return newMaximumSpent     A tuple containing the consideration items.
     */
    function generateOrder(
        address,
        SpentItem[] calldata minimumReceived,
        SpentItem[] calldata maximumSpent,
        bytes calldata // encoded based on the schemaID
    ) external returns (SpentItem[] memory newMinimumReceived, ReceivedItem[] memory newMaximumSpent) {
        // since this function alters state and assumes it is being called in the context of a Seaport order,
        // it must be called by the Seaport contract
        if (msg.sender != SEAPORT) {
            revert OnlySeaport();
        }
        // copy calldata arrays into memory for modification
        // TODO: should use WrappedNative token for maximumSpent, since smart contracts can reject Ether.
        newMinimumReceived = minimumReceived;
        // it's cheaper to allocate a new array than to copy the old one, which might contain incorrect
        // values anyway. Seaport will check returned values match the original.
        newMaximumSpent = allocateMaximumSpentArray(minimumReceived);

        // assume the final provided maximumSpent item is the fee paid, and copy its value
        uint256 totalFeePaid = maximumSpent[minimumReceived.length].amount;
        newMaximumSpent[minimumReceived.length].amount = totalFeePaid;
        // always pay the fee to the fee recipient
        newMaximumSpent[minimumReceived.length].recipient = payable(FEE_RECIPIENT);

        // calculate the average fee for all items (if multiple)
        uint256 feeAverage = totalFeePaid / minimumReceived.length;

        updateItems(minimumReceived, newMinimumReceived, newMaximumSpent, feeAverage);

        return (newMinimumReceived, newMaximumSpent);
    }

    function updateItems(
        SpentItem[] calldata minimumReceived,
        SpentItem[] memory newMinimumReceived,
        ReceivedItem[] memory newMaximumSpent,
        uint256 feeAverage
    ) internal {
        // populate the maximumSpent for each item
        for (uint256 i; i < minimumReceived.length;) {
            SpentItem calldata spentItem = minimumReceived[i];
            uint256 id;
            // if a wildcard item, get the cheapest item from the priority queue
            if (spentItem.itemType == ItemType.ERC721_WITH_CRITERIA) {
                id = feeRecord.metadata.rootKey();
                // update the returned item to be a concrete (non-criteria) item
                SpentItem memory wildcardItem = newMinimumReceived[i];
                wildcardItem.identifier = id;
                wildcardItem.itemType = ItemType.ERC721;
            } else {
                id = uint32(spentItem.identifier);
            }
            // get current compulsory price of the token
            (, uint256 price) = getCurrentFeeAndPrice(id);

            // get to whom the compulsory price should be paid
            address lastFeePayer = lastFeePayers[uint32(id)];
            if (lastFeePayer == address(0)) {
                lastFeePayer = ownerOf(id);
            }

            // set the amount and recipient of actual maxSpent
            ReceivedItem memory maximumSpentItem = newMaximumSpent[i];
            maximumSpentItem.amount = price;
            maximumSpentItem.recipient = payable(lastFeePayer);

            // update free transfer context for this id
            uint256 numTransfers = getNumFreeTransfers(id);
            unchecked {
                _setNumFreeTransfers(id, uint32(numTransfers + 1));
            }
            // update last fee payer for this id
            // TODO: shouldn't always use fulfiller, especially in matchorders context.
            // TODO: will have to figure out how to handle the matchOrders case so offerers' fees are recorded
            lastFeePayers[uint32(id)] = address(0);

            // take ownership of the token if not already owned by this contract
            address currentOwner = ownerOf(id);
            if (currentOwner != address(this)) {
                this.transferFrom(currentOwner, address(this), id);
            }

            // update priority queue with new fee for id
            feeRecord.update(id, feeAverage);
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @dev Ratifies an order with the specified offer, consideration, and
     *      optional context (supplied as extraData).
     *
     * @param offer         The offer items.
     *
     * @return ratifyOrderMagicValue The magic value returned by the contract
     *                               offerer.
     */
    function ratifyOrder(
        SpentItem[] calldata offer,
        ReceivedItem[] calldata,
        bytes calldata, // encoded based on the schemaID
        bytes32[] calldata,
        uint256
    ) external returns (bytes4 ratifyOrderMagicValue) {
        if (msg.sender != SEAPORT) {
            revert OnlySeaport();
        }
        for (uint256 i; i < offer.length;) {
            SpentItem memory spentItem = offer[i];
            // ensure no excess transfers, ie, fee evasion
            if (!_getFreeTransferContext(spentItem.identifier)) {
                revert TokenExceededFreeTransfers();
            }
            // clear the free transfer context for this id
            _clearFreeTransferContext(spentItem.identifier);
            // clear temporary storage for gas refund
            lastFeePayers[uint32(spentItem.identifier)] = address(0);
            unchecked {
                ++i;
            }
        }
        return ContractOffererInterface.ratifyOrder.selector;
    }

    /**
     * @notice Allocate an array of ReceivedItems, with length minimumReceived.length + 1,
     *         one for each item in minimumReceived, and one for the cumulative fee.
     * @param minimumReceived The minimum items that the caller is willing to
     */
    function allocateMaximumSpentArray(SpentItem[] calldata minimumReceived)
        internal
        pure
        returns (ReceivedItem[] memory consideration)
    {
        consideration = new ReceivedItem[](minimumReceived.length);
        uint256 newLength;
        unchecked {
            newLength = minimumReceived.length + 1;
        }
        // fill the array with empty ReceivedItems
        // TODO: use WETH
        for (uint256 i; i < minimumReceived.length;) {
            consideration[i] = ReceivedItem({
                itemType: ItemType.NATIVE,
                token: address(0),
                identifier: 0,
                amount: 0,
                recipient: payable(address(0))
            });

            unchecked {
                ++i;
            }
        }
    }

    /**
     * @dev View function to preview an order generated in response to a minimum
     *      set of received items, maximum set of spent items, and context
     *      (supplied as extraData).
     *
     *                        calling Seaport).
     * @param minimumReceived The minimum items that the caller is willing to
     *                        receive.
     * @param maximumSpent    The maximum items the caller is willing to spend.
     *
     * @return newMinimumReceived         A tuple containing the offer items.
     * @return newMaximumSpent A tuple containing the consideration items.
     */
    function previewOrder(
        address,
        address,
        SpentItem[] calldata minimumReceived,
        SpentItem[] calldata maximumSpent,
        bytes calldata // encoded based on the schemaID
    ) external view returns (SpentItem[] memory newMinimumReceived, ReceivedItem[] memory newMaximumSpent) {
        // since this function alters state and assumes it is being called in the context of a Seaport order,
        // it must be called by the Seaport contract
        if (msg.sender != SEAPORT) {
            revert OnlySeaport();
        }
        // TODO: should use WrappedNative token for maximumSpent, since smart contracts can reject Ether.
        newMinimumReceived = minimumReceived;
        newMaximumSpent = allocateMaximumSpentArray(minimumReceived);

        // read the total fee paid from the final provided maximumSpent item
        uint256 totalFeePaid = maximumSpent[minimumReceived.length].amount;
        newMaximumSpent[minimumReceived.length].amount = totalFeePaid;
        // always pay the fee to the fee recipient
        newMaximumSpent[minimumReceived.length].recipient = payable(FEE_RECIPIENT);

        // populate the maximumSpent for each item
        for (uint256 i; i < minimumReceived.length;) {
            SpentItem calldata spentItem = minimumReceived[i];
            uint256 id;
            // if a wildcard item, get the cheapest item from the priority queue
            if (spentItem.itemType == ItemType.ERC721_WITH_CRITERIA) {
                id = feeRecord.metadata.rootKey();
                // update the returned item to be a concrete (non-criteria) item
                SpentItem memory wildcardItem = newMinimumReceived[i];
                wildcardItem.identifier = id;
                wildcardItem.itemType = ItemType.ERC721;
            } else {
                id = uint32(spentItem.identifier);
            }
            // get current compulsory price of the token
            (, uint256 price) = getCurrentFeeAndPrice(id);

            // get to whom the compulsory price should be paid
            address lastFeePayer = lastFeePayers[uint32(id)];
            if (lastFeePayer == address(0)) {
                lastFeePayer = ownerOf(id);
            }

            // set the amount and recipient of actual maxSpent
            newMaximumSpent[i].amount = price;
            newMaximumSpent[i].recipient = payable(lastFeePayer);

            unchecked {
                ++i;
            }
        }
    }

    /**
     * @dev Gets the metadata for this contract offerer.
     *
     * @return name    The name of the contract offerer.
     * @return schemas The schemas supported by the contract offerer.
     */
    function getSeaportMetadata()
        external
        view
        returns (
            string memory name,
            Schema[] memory schemas // map to Seaport Improvement Proposal IDs
        )
    {
        return (_name, schemas);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ContractOffererInterface, AbstractERC721HF)
        returns (bool)
    {
        return
            interfaceId == type(ContractOffererInterface).interfaceId || AbstractERC721HF.supportsInterface(interfaceId);
    }
}
