// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {AbstractHarbergerFee} from "./AbstractHarbergerFee.sol";
import {ERC721} from "solady/tokens/ERC721.sol";
import {ERC2981} from "./lib/ERC2981.sol";
import {MinHeapMap, Heap} from "sol-heap/MinHeapMap.sol";
import {Node, NodeType} from "sol-heap/lib/NodeType.sol";
import {HeapMetadata, HeapMetadataType} from "sol-heap/lib/HeapMetadataType.sol";

abstract contract AbstractERC721HF is ERC721, AbstractHarbergerFee {
    using MinHeapMap for Heap;
    using HeapMetadataType for HeapMetadata;

    error InvalidPayment();
    error NativeTransferFailed();

    string _name;
    string _symbol;

    function name() public view virtual override returns (string memory) {
        return _name;
    }

    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    function tokenURI(uint256) public view virtual override returns (string memory) {
        return "";
    }

    function mint(address to, uint32 tokenId) public virtual onlyOwner {
        feeRecord.insert(tokenId, type(uint160).max);
        _mint(to, tokenId);
    }

    ////////////////////
    // FREE TRANSFERS //
    ////////////////////

    function setNumFreeTransfers(uint256 tokenId, uint32 numOverrides) public virtual onlyOwner {
        if (!_exists(tokenId)) {
            revert TokenDoesNotExist();
        }
        _setNumFreeTransfers(tokenId, numOverrides);
    }

    function getNumFreeTransfers(uint256 tokenId) public view virtual returns (uint96) {
        if (!_exists(tokenId)) {
            revert TokenDoesNotExist();
        }
        return uint32(_getExtraData(tokenId));
    }

    function _setNumFreeTransfers(uint256 tokenId, uint32 numOverrides) internal {
        _setExtraData(tokenId, (1 << 32) | numOverrides);
    }

    function _clearFreeTransferContext(uint256 tokenId) internal {
        _setExtraData(tokenId, 0);
    }

    function _getFreeTransferContext(uint256 tokenId) public view virtual returns (bool) {
        uint96 extraData = _getExtraData(tokenId);
        return bool((extraData >> 32) == 1);
    }

    //////////////
    // PURCHASE //
    //////////////

    function purchaseToken(uint256 tokenId) public payable virtual {
        if (!_exists(tokenId)) {
            revert TokenDoesNotExist();
        }
        _purchaseToken(tokenId);
    }

    function purchaseCheapest() public payable virtual {
        HeapMetadata metadata = feeRecord.metadata;
        if (metadata.size() == 0) {
            revert TokenDoesNotExist();
        }
        uint256 cheapestTokenId = metadata.rootKey();
        _purchaseToken(cheapestTokenId);
    }

    function _purchaseToken(uint256 tokenId) internal virtual {
        (uint256 fee, uint256 currentPrice) = getCurrentFeeAndPrice(tokenId);
        uint256 newFee;
        unchecked {
            uint256 cumulativePayment = fee + currentPrice;
            if (msg.value < cumulativePayment) {
                revert InvalidPayment();
            }
            newFee = msg.value - currentPrice;
        }
        feeRecord.update(tokenId, newFee);
        // external call to self bypasses fee reset, which avoids an extra SSTORE+SLOAD vs incrementing
        // numFeeOverrides
        address oldOwner = _ownerOf(tokenId);
        this.transferFrom(_ownerOf(tokenId), msg.sender, tokenId);
        (bool success,) = oldOwner.call{value: currentPrice}("");
        if (!success) {
            revert NativeTransferFailed();
        }
    }

    //////////////
    // FEE PAID //
    //////////////

    function updateFeePaid(uint256 tokenId) public payable {
        if (!_exists(tokenId)) {
            revert TokenDoesNotExist();
        }
        Node node = feeRecord.get(tokenId);
        uint256 fee = node.value();
        unchecked {
            feeRecord.update(tokenId, fee + msg.value);
        }
    }

    function overrideFeePaid(uint256 tokenId, uint256 newFee) public onlyOwner {
        if (!_exists(tokenId)) {
            revert TokenDoesNotExist();
        }
        feeRecord.update(tokenId, newFee);
    }

    ///////////////
    // OVERRIDES //
    ///////////////

    function isApprovedForAll(address _owner, address operator) public view virtual override returns (bool) {
        return address(this) == operator || super.isApprovedForAll(_owner, operator);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721, ERC2981) returns (bool) {
        return ERC721.supportsInterface(interfaceId) || ERC2981.supportsInterface(interfaceId);
    }

    function _beforeTokenTransfer(address from, address, uint256 tokenId) internal virtual override {
        // mints and purchases (self-transfers) don't reset the fee
        if (!(from == address(0) || msg.sender == address(this))) {
            // direct transfers from the owner don't reset the fee
            if (msg.sender != _ownerOf(tokenId)) {
                // allow certain contexts to bypass the fee, but only allow it to be transferred a certain number of times
                // useful for things like atomically filling multiple sales
                uint32 numRemainingFreeTransfers = uint32(getNumFreeTransfers(tokenId));

                if (numRemainingFreeTransfers == 0) {
                    // reset fee and clear free transfer context, in case it was set
                    feeRecord.update(tokenId, 0);
                    _clearFreeTransferContext(tokenId);
                } else {
                    unchecked {
                        _setNumFreeTransfers(tokenId, numRemainingFreeTransfers - 1);
                    }
                }
            }
        }
    }
}
