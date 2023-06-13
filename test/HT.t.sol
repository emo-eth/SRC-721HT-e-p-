// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Test} from "forge-std/Test.sol";
// import {HT} from "../src/HT.sol";
import {HTImpl} from "./helpers/HTImpl.sol";

contract HTTest is Test {
    HTImpl test;

    receive() external payable {}

    function setUp() public {
        test = new HTImpl(100, address(this), payable(address(this)));
    }

    function testStaticGetters(uint256 feeBps) public {
        feeBps = bound(feeBps, 1, 10_000);
        test = new HTImpl(feeBps, address(this), payable(address(this)));
        assertEq(test.getFeeFromPrice(1234e9), (1234e9 * feeBps) / 10_000);
        assertEq(test.getPriceFromFee(1234e9), (1234e9 * 10_000) / feeBps);
    }

    function testDynamicGetters(uint256 feeBps) public {
        feeBps = bound(feeBps, 1, 10_000);
        test = new HTImpl(feeBps, address(this), payable(address(this)));
        test.setFee(1, 1234e9);
        test.setFee(2, 5678e9);
        (address recip, uint256 fee) = test.royaltyInfo(1, 1234e9);
        assertEq(recip, address(this));
        assertEq(fee, (1234e9 * feeBps) / 10_000);
        (recip, fee) = test.royaltyInfo(2, 5678e9);
        assertEq(recip, address(this));
        assertEq(fee, (5678e9 * feeBps) / 10_000);

        (uint256 currFee, uint256 currPrice) = test.getCurrentFeeAndPrice(1);
        assertEq(currFee, 1234e9);
        assertEq(currPrice, 1234e9 * 10_000 / feeBps);
        currPrice = test.getResalePrice(1);
        assertEq(currPrice, 1234e9 * 10_000 / feeBps);

        (currFee, currPrice) = test.getCurrentFeeAndPrice(2);
        assertEq(currFee, 5678e9);
        assertEq(currPrice, 5678e9 * 10_000 / feeBps);
        currPrice = test.getResalePrice(2);
        assertEq(currPrice, 5678e9 * 10_000 / feeBps);
        currPrice = test.getResalePrice(2);
        assertEq(currPrice, 5678e9 * 10_000 / feeBps);
    }
}
