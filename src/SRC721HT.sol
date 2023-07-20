// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {ContractOffererInterface, IERC165} from "seaport-types/interfaces/ContractOffererInterface.sol";
import {ERC721HarbergerFee} from "./ERC721HT.sol";
import {AbstractSRC721HF} from "./AbstractSRC721HF.sol";
import {SpentItem, ReceivedItem, Schema} from "seaport-types/lib/ConsiderationStructs.sol";
import {ItemType} from "seaport-types/lib/ConsiderationEnums.sol";
import {MinHeapMap, Heap} from "sol-heap/MinHeapMap.sol";
import {Node, NodeType} from "sol-heap/lib/NodeType.sol";

contract SRC721HT is ERC721HarbergerFee, AbstractSRC721HF {
    constructor(address seaport, uint256 feeBps, address initialOwner, address payable feeRecipient)
        AbstractSRC721HF(seaport)
        ERC721HarbergerFee(feeBps, initialOwner, feeRecipient)
    {}

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(AbstractSRC721HF, ERC721HarbergerFee)
        returns (bool)
    {
        return AbstractSRC721HF.supportsInterface(interfaceId);
    }
}
