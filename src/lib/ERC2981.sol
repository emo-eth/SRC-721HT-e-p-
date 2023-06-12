// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IERC2981} from "../interfaces/IERC2981.sol";
import {IERC165} from "forge-std/interfaces/IERC165.sol";

abstract contract ERC2981 is IERC2981 {
    function supportsInterface(bytes4 interfaceId) public view virtual override(IERC165) returns (bool) {
        return interfaceId == type(IERC2981).interfaceId || interfaceId == type(IERC165).interfaceId;
    }
}
