// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Test} from "forge-std/Test.sol";
// import {HT} from "../src/HarbergerFee.sol";
import {eHTImpl} from "./helpers/eHTImpl.sol";

contract HTTest is Test {
    uint256 confirmationWindowOpenTimestamp;
    uint256 confirmationWindowDeadlineTimestamp;
    uint256 auctionDeadlineTimestamp;
    uint256 finalDeadlineTimestamp;

    eHTImpl test;

    receive() external payable {}

    function setUp() public {
        vm.warp(10_000);
        confirmationWindowOpenTimestamp = block.timestamp + 1 hours;
        confirmationWindowDeadlineTimestamp = block.timestamp + 2 hours;
        auctionDeadlineTimestamp = block.timestamp + 3 hours;
        finalDeadlineTimestamp = block.timestamp + 4 hours;

        test =
        new eHTImpl(confirmationWindowOpenTimestamp, confirmationWindowDeadlineTimestamp,auctionDeadlineTimestamp,finalDeadlineTimestamp,100, address(this), payable(address(this)));
    }

    function testStaticGetters(uint256 feeBps) public {
        feeBps = bound(feeBps, 1, 10_000);
        test =
        new eHTImpl(confirmationWindowOpenTimestamp, confirmationWindowDeadlineTimestamp,auctionDeadlineTimestamp,finalDeadlineTimestamp,feeBps, address(this), payable(address(this)));
        assertEq(test.getFeeFromPrice(1234e9), (1234e9 * feeBps) / 10_000);
        assertEq(test.getPriceFromFee(1234e9), (1234e9 * 10_000) / feeBps);
    }

    function testDynamicGetters(uint256 feeBps) public {
        feeBps = bound(feeBps, 1, 10_000);
        test =
        new eHTImpl(confirmationWindowOpenTimestamp, confirmationWindowDeadlineTimestamp,auctionDeadlineTimestamp,finalDeadlineTimestamp,feeBps, address(this), payable(address(this)));
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

    function testIsConfirmed() public {
        test.setFee(1, type(uint160).max);
        assertTrue(test.isConfirmed(1));
    }

    function testGetAuctionPriceFromFee() public {
        // confirmed
        test.setFee(1, 0);
        test.confirm(1);
        assertEq(
            test.getAuctionPriceFromFee(100, finalDeadlineTimestamp + 1),
            type(uint256).max,
            "auction price after final deadline should be max"
        );

        assertEq(
            test.getAuctionPriceFromFee(100, auctionDeadlineTimestamp),
            0,
            "auction price after auction deadline should be 0"
        );

        assertEq(
            test.getAuctionPriceFromFee(100, confirmationWindowDeadlineTimestamp),
            100 * 10_000 / 100,
            "auction price at confirmation deadline should be whole"
        );

        vm.warp(finalDeadlineTimestamp + 1);
        assertEq(
            test.getAuctionPriceFromFee(100), type(uint256).max, "auction price after final deadline should be whole"
        );
    }

    function testGetPriceFromFee() public {
        // before confirmation window
        uint160 fee = 100;
        assertEq(test.getPriceFromFee(fee), (fee * 10_000) / fee);
        // during confirmation window
        vm.warp(confirmationWindowOpenTimestamp);
        assertEq(test.getPriceFromFee(fee), (fee * 10_000) / fee);
        // after confirmation window
        vm.warp(confirmationWindowDeadlineTimestamp);
        assertEq(test.getPriceFromFee(fee), (fee * 10_000) / fee);
        assertEq(test.getPriceFromFee(type(uint160).max), type(uint256).max);
    }
}
