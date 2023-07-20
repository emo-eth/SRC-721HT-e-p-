// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {ContractOffererInterface, IERC165} from "seaport-types/interfaces/ContractOffererInterface.sol";
import {ERC721HFe} from "./ERC721HTe.sol";
import {AbstractSRC721HF} from "./AbstractSRC721HF.sol";
import {SpentItem, ReceivedItem, Schema} from "seaport-types/lib/ConsiderationStructs.sol";
import {ItemType} from "seaport-types/lib/ConsiderationEnums.sol";
import {MinHeapMap, Heap} from "sol-heap/MinHeapMap.sol";
import {Node, NodeType} from "sol-heap/lib/NodeType.sol";

contract SRC721HFe is ERC721HFe, AbstractSRC721HF {
    constructor(
        address seaport,
        uint256 confirmationOpen,
        uint256 confirmationDeadline,
        uint256 auctionDeadline,
        uint256 finalDeadline,
        uint256 feeBps,
        address initialOwner,
        address payable feeRecipient
    )
        AbstractSRC721HF(seaport)
        ERC721HFe(
            confirmationOpen,
            confirmationDeadline,
            auctionDeadline,
            finalDeadline,
            feeBps,
            initialOwner,
            feeRecipient
        )
    {}

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(AbstractSRC721HF, ERC721HFe)
        returns (bool)
    {
        return AbstractSRC721HF.supportsInterface(interfaceId);
    }
}
