//SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {OracleLib} from "../../src/libraries/OracleLib.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract OraceLibTest is Test {
    using OracleLib for AggregatorV3Interface;

    MockV3Aggregator public aggregator;
    uint8 public constant DECIMALS = 8;
    int256 public constant INITIAL_PRICE = 2000 ether;

    function setUp() external {
        aggregator = new MockV3Aggregator(DECIMALS, INITIAL_PRICE);
    }

    function testgetTimeOut() public {
        uint256 expectedTimeout = 3 hours;
        uint256 actualTimeout = OracleLib.getTimeout();
        assertEq(expectedTimeout, actualTimeout);
    }

    function testRevertsIfPriceIsStale() public {
        vm.warp(block.timestamp + 4 hours);
        vm.roll(block.number + 1);

        vm.expectRevert(OracleLib.OracleLib__StalePrice.selector);
        AggregatorV3Interface(address(aggregator)).staleCheckLastestRoundData();
    }

    function testRevertsOnBadRoundAnswer() public {
        uint80 _roundId = 0;
        int256 _answer = 0;
        uint256 _timestamp = 0;
        uint256 _startedAt = 0;
        aggregator.updateRoundData(_roundId, _answer, _timestamp, _startedAt);

        vm.expectRevert(OracleLib.OracleLib__StalePrice.selector);
        AggregatorV3Interface(address(aggregator)).staleCheckLastestRoundData();
    }
}