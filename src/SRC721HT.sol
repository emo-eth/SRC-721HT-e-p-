// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {ContractOffererInterface, IERC165} from "seaport-types/interfaces/ContractOffererInterface.sol";
import {ERC721HT} from "./ERC721HT.sol";
import {SpentItem, ReceivedItem, Schema} from "seaport-types/lib/ConsiderationStructs.sol";
import {ItemType} from "seaport-types/lib/ConsiderationEnums.sol";
import {MinHeapMap, Heap} from "sol-heap/MinHeapMap.sol";
import {Node, NodeType} from "sol-heap/lib/NodeType.sol";

contract SRC721HT is ERC721HT, ContractOffererInterface {
    using MinHeapMap for Heap;

    error OnlySeaport();

    error TokenExceededFreeTransfers();

    address immutable SEAPORT;

    mapping(uint32 id => address lastFeePayer) internal lastFeePayers;

    constructor(uint256 feeBps, address initialOwner, address payable feeRecipient)
        ERC721HT(feeBps, initialOwner, feeRecipient)
    {
        SEAPORT = msg.sender;
    }

    /**
     * @dev Generates an order with the specified minimum and maximum spent
     *      items, and optional context (supplied as extraData).
     *
     * @param minimumReceived The minimum items that the caller is willing to
     *                        receive.
     * @param maximumSpent    The maximum items the caller is willing to spend.
     *
     * @return offer         A tuple containing the offer items.
     * @return consideration A tuple containing the consideration items.
     */
    function generateOrder(
        address,
        SpentItem[] calldata minimumReceived,
        SpentItem[] calldata maximumSpent,
        bytes calldata // encoded based on the schemaID
    ) external returns (SpentItem[] memory offer, ReceivedItem[] memory consideration) {
        if (msg.sender != SEAPORT) {
            revert OnlySeaport();
        }
        // TODO: should use WrappedNative token for maximumSpent, since smart contracts can reject Ether
        offer = minimumReceived;
        consideration = allocateReceivedItems(minimumReceived);
        // read the total fee from the final provided maximumSpent item
        consideration[minimumReceived.length].amount = maximumSpent[minimumReceived.length].amount;
        consideration[minimumReceived.length].recipient = payable(FEE_RECIPIENT);
        // calculate the average fee for all items (if multiple)
        uint256 feeAverage = maximumSpent[minimumReceived.length].amount / minimumReceived.length;

        // populate the maximumSpent for each item
        for (uint256 i; i < minimumReceived.length;) {
            SpentItem calldata spentItem = minimumReceived[i];
            uint256 id;
            // if a wildcard order, get the cheapest item from the priority queue
            if (spentItem.itemType == ItemType.ERC721_WITH_CRITERIA) {
                id = feeRecord.metadata.rootKey();
            } else {
                id = uint32(spentItem.identifier);
            }
            // get price of the token
            (, uint256 price) = getCurrentFeeAndPrice(id);

            // get to whom the price should be paid
            address lastFeePayer = lastFeePayers[uint32(id)];
            if (lastFeePayer == address(0)) {
                lastFeePayer = ownerOf(id);
            }
            // set the amount and recipient of actual maxSpent
            consideration[i].amount = price;
            consideration[i].recipient = payable(lastFeePayer);
            uint256 numTransfers = getNumFreeTransfers(id);
            unchecked {
                _setNumFreeTransfers(id, uint32(numTransfers + 1));
            }
            address currentOwner = _ownerOf(id);
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
     * @notice Allocate an array of ReceivedItems, with length minimumreceived.length + 1,
     *         one for each item in minimumReceived, and one for the cumulative fee.
     * @param minimumReceived The minimum items that the caller is willing to
     */
    function allocateReceivedItems(SpentItem[] calldata minimumReceived)
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
     * @param caller          The address of the caller (e.g. Seaport).
     * @param fulfiller       The address of the fulfiller (e.g. the account
     *                        calling Seaport).
     * @param minimumReceived The minimum items that the caller is willing to
     *                        receive.
     * @param maximumSpent    The maximum items the caller is willing to spend.
     * @param context         Additional context of the order.
     *
     * @return offer         A tuple containing the offer items.
     * @return consideration A tuple containing the consideration items.
     */
    function previewOrder(
        address caller,
        address fulfiller,
        SpentItem[] calldata minimumReceived,
        SpentItem[] calldata maximumSpent,
        bytes calldata context // encoded based on the schemaID
    ) external view returns (SpentItem[] memory offer, ReceivedItem[] memory consideration) {}

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
        override(ContractOffererInterface, ERC721HT)
        returns (bool)
    {
        return interfaceId == type(ContractOffererInterface).interfaceId || ERC721HT.supportsInterface(interfaceId);
    }
}
