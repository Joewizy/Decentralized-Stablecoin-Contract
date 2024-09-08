// SPDX-License-Identifier: MIT

// Have our invariants aka the PROPERTIES
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {Handler} from "./Handler.t.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";

contract Invariants is StdInvariant, Test{
    DecentralizedStableCoin dsc;
    HelperConfig config;
    DeployDSC deployer;
    DSCEngine engine;
    Handler handler;

    address weth;
    address wbtc; 

    function setUp() external {
        deployer = new DeployDSC();
        (dsc, engine, config) = deployer.run();
        (,, weth, wbtc,) = config.activeNetworkConfig();
        handler = new Handler(dsc, engine);
        targetContract(address(handler));
    }

    function invariant_protocolMustHaveMoreValueThanTotalSupply() external view {
        uint256 totalDscSupply = dsc.totalSupply();
        uint256 totalWethDeposited = IERC20(weth).balanceOf(address(engine));
        uint256 totalWbtcDeposited = IERC20(wbtc).balanceOf(address(engine));

        uint256 wethValue = engine.getUsdValue(weth, totalWethDeposited);
        uint256 wbtcValue = engine.getUsdValue(wbtc, totalWbtcDeposited);
        uint256 timesMinted = handler.timesMintIsCalled();
        
        console.log("Total Supply:", totalDscSupply);
        console.log("WethDeposited:", totalWethDeposited);
        console.log("WbtcDeposited:", totalWbtcDeposited);
        console.log("weth in usd: ", wethValue);
        console.log("wbtc in usd: ", wbtcValue);
        console.log("Times mint called: ", timesMinted);

        assert(wethValue + wbtcValue >= totalDscSupply);
    }
    
    function invariant_gettersShouldNotRevert() public {
        engine.getAdditionalFeedPrecision();
        engine.getCollateralTokens();
        engine.getLiquidationBonus();
        engine.getLiquidationPrecision();
        engine.getLiquidationThreshold();
        engine.getMinHealthFactor();
        engine.getPrecision();
        engine.getDsc();
    }
}

