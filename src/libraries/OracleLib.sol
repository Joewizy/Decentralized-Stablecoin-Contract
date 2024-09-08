// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/*
* @title OracleLib
* @author Joseph Gimba
* @notice The function of this library is to monitor the Chainlink Oracle for stale data.
* If a price is stale, the function would revert, and render the DSCEngine unusable
* We want to freeze the DSCEngine if the prizes becomes stale
*/

library OracleLib{
    error OracleLib__StalePrice();

    uint256 private constant TIMEOUT = 3 hours; // 3 * 60 * 60 = 10800s

    function staleCheckLastestRoundData(AggregatorV3Interface priceFeed) public view returns(uint80, int256, uint256, uint256, uint80){
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) = priceFeed.latestRoundData();

        if (updatedAt == 0 || answeredInRound < roundId){
            revert OracleLib__StalePrice();
        }
        uint256 secondsSince = block.timestamp - updatedAt;
        if(secondsSince > TIMEOUT){
            revert OracleLib__StalePrice();
        }
        return (roundId, answer, startedAt, updatedAt, answeredInRound);
    }
    
    //GETTER FUNCTIONS
    function getTimeout() public pure returns(uint256){
        return TIMEOUT;
    }
}