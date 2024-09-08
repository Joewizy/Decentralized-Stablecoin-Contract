//SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {MockFailedTransferFrom} from "../mocks/MockFailedTransferFrom.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";
import {MockMoreDebtDSC} from "../mocks/MockMoreDebtDSC.sol";

contract DSCEngineTest is Test{
    DeployDSC deployer;
    DSCEngine engine;
    DecentralizedStableCoin dsc;
    HelperConfig config;

    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    address weth;
    address wbtc;

    address public USER = address(1);
    address public MALICIOUS_USER = makeAddr("malicousUserAddress");
    uint256 AMOUNT_COLLATERAL = 10 ether;
    uint256 amountToMint = 100 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 100 ether;
    uint256 public constant MIN_HEALTH_FACTOR = 1e18;
    uint256 public constant LIQUIDATION_THRESHOLD = 50;
    uint256 public constant PRECISION = 1e18;

    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant LIQUIDATION_BONUS = 10; // 10% bonus since we divide by 100

    // Liquidation
    address public liquidator = makeAddr("liquidator");
    uint256 public collateralToCover = 20 ether;

    //EVENTS
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralReedemed(
        address indexed redeemFrom, address indexed redeemedTo, address indexed token, uint256 amount
    );

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, engine, config) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth, wbtc,) = config.activeNetworkConfig();

        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
    }

    /////////////////////////
    // CONSTRUCTOR TESTS ///
    ////////////////////////
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function testRevertIfTokenLengthDoesntMatchPriceFeeds() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);

        vm.expectRevert(DSCEngine.DSCEngine__tokenAddressesAndPriceFeedAddressesMustBeTheSameLength.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    ///////////////////
    // PRICE TESTS ///
    //////////////////

    function testGetUsdValue() public {
        uint256 ethAmount = 20e18;
        // 20e18 ETH * $2000/ETH = 40000e18
        uint256 expectedUsd = 40000e18;
        uint256 actualUsd = engine.getUsdValue(weth, ethAmount);
        assertEq(expectedUsd, actualUsd);
    }

    function testgetTokenAmountFromUsd() public {
        uint256 usdAmount = 100 ether;
        // Get 100$ worth of WETH (weth/usd = 2000) => Should be 0.05 WETH
        uint256 expectedWeth = 0.05 ether;
        uint256 actualWeth = engine.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(expectedWeth, actualWeth);
    }

    ///////////////////////////////
    // DEPOSIT-COLLATERAL TESTS ///
    //////////////////////////////

    modifier collateralDeposited() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testRevertIfCollateralZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        engine.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertsWithUnapprovedCollateral() public {
        ERC20Mock joeToken = new ERC20Mock("Joewi", "JOE", USER, AMOUNT_COLLATERAL);
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        engine.depositCollateral(address(joeToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testCanDepositCollateralWithoutMinting() public collateralDeposited {
        uint256 userBalance = dsc.balanceOf(USER);
        assertEq(userBalance, 0);
    }

    //  function testRevertsIfTransferFromFails() public {
    //     // Arrange - Setup
    //     address owner = msg.sender;
    //     vm.prank(owner);
    //     MockFailedTransferFrom mockDsc = new MockFailedTransferFrom();
    //     tokenAddresses = [address(mockDsc)];
    //     priceFeedAddresses = [wethUsdPriceFeed];
    //     vm.prank(owner);
    //     DscEngine mockDsce = new DscEngine(tokenAddresses, priceFeedAddresses, address(mockDsc));
    //     mockDsc.mint(user, AMOUNT_COLLATERAL);

    //     vm.prank(owner);
    //     mockDsc.transferOwnership(address(mockDsce)); // Make mockDscEngine the owner of the mockDsc contract
    //     // Arrange - User
    //     vm.startPrank(user);
    //     ERC20Mock(address(mockDsc)).approve(address(mockDsce), AMOUNT_COLLATERAL);
    //     // Act / Assert
    //     vm.expectRevert(DscEngine.DscEngine__TransferFailed.selector);
    //     mockDsce.depositCollateral(address(mockDsc), AMOUNT_COLLATERAL);
    //     vm.stopPrank();
    // }

    function testCollateralCanDepositAndGetAccountInfo() public collateralDeposited {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = engine.getAccountInformation(USER);

        uint256 expectedTotalDscMinted = 0;
        uint256 expectedDepositAmount = engine.getTokenAmountFromUsd(weth, collateralValueInUsd);

        assertEq(totalDscMinted, expectedTotalDscMinted);
        assertEq(AMOUNT_COLLATERAL, expectedDepositAmount);
    }

    /////////////////////////////////////////
    // depositCollateralAndMintDsc TESTS ///
    ///////////////////////////////////////

    function testRevertsIfMintDscBreaksHealthFactor() public {
        (, int256 price,,,) = MockV3Aggregator(ethUsdPriceFeed).latestRoundData();
        amountToMint =
            (AMOUNT_COLLATERAL * (uint256(price) * engine.getAdditionalFeedPrecision())) / engine.getPrecision();
        vm.startPrank(USER);

        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        uint256 expectedHealthFactor =
            engine.calculateHealthFactor(amountToMint, engine.getUsdValue(weth, AMOUNT_COLLATERAL));
        // Add logs to debug values
        console.log("Price:", price);
        console.log("Amount to Mint:", amountToMint);
        console.log("Expected Health Factor:", expectedHealthFactor);
        console.log("MinHealthFactor:", MIN_HEALTH_FACTOR);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, expectedHealthFactor));
        engine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, amountToMint);

        vm.stopPrank();
    }

    modifier depositedCollateralAndMintedDsc() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, amountToMint);
        dsc.approve(address(engine), amountToMint);
        vm.stopPrank();
        _;
    }

    function testCanMintWithDepositedCollateral() public depositedCollateralAndMintedDsc {
        uint256 userBalance = dsc.balanceOf(USER);
        assertEq(userBalance, amountToMint);
        uint256 mintedDSC = engine.getDscMinted(USER);
        console.log("DSC Minted:", mintedDSC);
    }

    ///////////////////
    // MintDsc Tests //
    //////////////////

    function testMintDsc() public depositedCollateralAndMintedDsc {
        vm.startPrank(USER);
        uint256 actualDscMinted = engine.getDscMinted(USER);
        vm.stopPrank();
        assertEq(actualDscMinted, amountToMint);
    }

    function testRevertIfMintAmountIsZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, amountToMint);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        engine.mintDsc(0);
        vm.stopPrank();
    }

    function testRevertsIfMintAmountBreaksHealthFactor() public collateralDeposited {
        (, int256 price,,,) = MockV3Aggregator(ethUsdPriceFeed).latestRoundData();
        amountToMint =
            (AMOUNT_COLLATERAL * (uint256(price) * engine.getAdditionalFeedPrecision())) / engine.getPrecision();
        vm.startPrank(USER);

        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        uint256 expectedHealthFactor =
            engine.calculateHealthFactor(amountToMint, engine.getUsdValue(weth, AMOUNT_COLLATERAL));

        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, expectedHealthFactor));
        engine.mintDsc(amountToMint);
        vm.stopPrank();
    }

    ///////////////////
    // BurnDsc Tests //
    //////////////////
    function testRevertsIfBurnAmountIsZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        engine.burnDsc(0);
        vm.stopPrank();
    }

    function testCantBurnMoreThanBalance() public depositedCollateralAndMintedDsc {
        vm.startPrank(USER);
        dsc.approve(address(engine), amountToMint);
        vm.expectRevert();
        engine.burnDsc(1000e18);
    }

    function testBurnDsc() public depositedCollateralAndMintedDsc {
        vm.startPrank(USER);
        dsc.approve(address(engine), amountToMint);
        engine.burnDsc(amountToMint);
        uint256 actualDscBalance = dsc.balanceOf(USER);
        vm.stopPrank();
        assertEq(actualDscBalance, 0);
    }

    /////////////////////////////
    // reedeemCollateral Tests //
    ////////////////////////////

    // function testRevertsIfTransferFailed() public  {
    //     address owner = address(this);

    //     vm.startPrank(owner);
    //     MockFailedTransferFrom mockFailed = new MockFailedTransferFrom();
    //     tokenAddresses = [address(mockFailed)];
    //     priceFeedAddresses = [ethUsdPriceFeed];
    //     DSCEngine mockEngine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(mockFailed));
    //     mockFailed.transferOwnership(address(mockEngine));
    //     mockFailed.mint(USER, STARTING_ERC20_BALANCE);
    //     vm.stopPrank();

    //     vm.startPrank(USER);
    //     ERC20Mock(address(mockFailed)).approve(address(mockEngine), AMOUNT_COLLATERAL);
    //     mockEngine.depositCollateral(address(mockFailed), AMOUNT_COLLATERAL);
    //     vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
    //     mockEngine.redeemCollateral(address(mockFailed), AMOUNT_COLLATERAL);
    //     vm.stopPrank();
    // }

    function testCollateralDepositedCantBelowZero() public {
        vm.startPrank(USER);
        console.log("user weth balance: ", ERC20Mock(weth).balanceOf(USER));
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        console.log("collateral deposited");
        vm.expectRevert();
        engine.redeemCollateral(weth, AMOUNT_COLLATERAL + 1); // cannot reedeem more than deposited collateral
        vm.stopPrank();
    }

    function testRevertsIfRedeemAmountIsZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        engine.redeemCollateral(weth, 0);
    }

    function testRedeemCollateral() public collateralDeposited {
        vm.startPrank(USER);
        engine.redeemCollateral(weth, AMOUNT_COLLATERAL);
        uint256 userBalance = ERC20Mock(address(weth)).balanceOf(USER);
        assertEq(userBalance, STARTING_ERC20_BALANCE);
    }

    function testEmitCollateralWithCorrectArgs() public collateralDeposited {
        vm.expectEmit(true, true, true, true, address(engine));
        emit CollateralReedemed(USER, USER, weth, AMOUNT_COLLATERAL);
        vm.startPrank(USER);
        engine.redeemCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    ///////////////////////////////////////
    //  redeemCollateralAndBurnDsctests  //
    ///////////////////////////////////////

    function testMustRedeemMoreThanZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        engine.reedeemCollateralAndBurnDsc(weth, 0, amountToMint);
    }

    function testRedeemCollateralAndBurnDsc() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, amountToMint);
        dsc.approve(address(engine), amountToMint);
        engine.reedeemCollateralAndBurnDsc(weth, AMOUNT_COLLATERAL, amountToMint);
        uint256 userDscBalance = ERC20Mock(address(weth)).balanceOf(USER);
        uint256 userBurntBalance = dsc.balanceOf(USER);
        assertEq(userDscBalance, amountToMint);
        assertEq(userBurntBalance, 0);
    }

    //////////////////////////
    //  healthFactor TESTS  //
    /////////////////////////

    function testHealthFactorFunctionsProperly() public depositedCollateralAndMintedDsc {
        vm.startPrank(USER);
        //collateral = $20000 * 0.5 / 100 (dscMinted) = 100
        uint256 expectedHealthFactor = 100 ether;
        uint256 healthFactor = engine.getHealthFactor(USER);
        assertEq(expectedHealthFactor, healthFactor);
        vm.stopPrank();
    }

    function testHealthFactorCanGoBelowOne() public depositedCollateralAndMintedDsc {
        int256 ethUsdUpdatedPrice = 18e8; // 1ETH = $18 yup that should work.
        // Rememeber, we need $200 at all times if we have $100 of debt

        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);
        uint256 userHealthFactor = engine.getHealthFactor(USER);
        // 180*50 (LIQUIDATION_THRESHOLD) / 100 (LIQUIDATION_PRECISION) / 100 (PRECISION) = 90 / 100 (totalDscMinted) =
        // 0.9 = 9e17

        assert(userHealthFactor == 9e17);
    }

    ///////////////////////
    // Liquidation Tests //
    ///////////////////////

    function testMustImproveHealthFactorOnLiquidation() public {
        // Arrange - Setup Mock Contracts
        MockMoreDebtDSC mockDsc = new MockMoreDebtDSC(ethUsdPriceFeed);
        tokenAddresses = [weth];
        priceFeedAddresses = [ethUsdPriceFeed];
        address owner = msg.sender;

        // Deploy DSCEngine with MockMoreDebtDSC
        vm.prank(owner);
        DSCEngine mockDsce = new DSCEngine(tokenAddresses, priceFeedAddresses, address(mockDsc));
        mockDsc.transferOwnership(address(mockDsce));

        // Arrange - User
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(mockDsce), AMOUNT_COLLATERAL);
        mockDsce.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, amountToMint);
        vm.stopPrank();

        // Arrange - Liquidator
        uint256 liquidatorCollateral = 1 ether;
        ERC20Mock(weth).mint(liquidator, liquidatorCollateral);

        vm.startPrank(liquidator);
        ERC20Mock(weth).approve(address(mockDsce), liquidatorCollateral);
        uint256 debtToCover = 10 ether;
        mockDsce.depositCollateralAndMintDsc(weth, liquidatorCollateral, amountToMint);
        mockDsc.approve(address(mockDsce), debtToCover);

        // Act - Update Price Feed
        int256 ethUsdUpdatedPrice = 18e8; // 1 ETH = $18
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);

        // Act/Assert - Attempt Liquidation
        vm.expectRevert(DSCEngine.DSCEngine__HealthDidNotImprove.selector);
        mockDsce.liquidate(weth, USER, debtToCover);
        vm.stopPrank();
    }

    function testRevertIfHealthFactorIsOkay() public depositedCollateralAndMintedDsc {
        ERC20Mock(weth).mint(liquidator, collateralToCover);

        vm.startPrank(liquidator);
        ERC20Mock(weth).approve(address(engine), collateralToCover);
        engine.depositCollateralAndMintDsc(weth, collateralToCover, amountToMint);
        dsc.approve(address(engine), amountToMint);

        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorOk.selector);
        engine.liquidate(weth, USER, amountToMint);
        vm.stopPrank();
    }

    modifier liquidated() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, amountToMint);
        dsc.approve(address(engine), amountToMint);
        vm.stopPrank();

        int256 ethUsdUpdatedPrice = 18e8; // 1ETH = $18
        // Update ETH price feed
        MockV3Aggregator ethPriceFeed = MockV3Aggregator(ethUsdPriceFeed);
        ethPriceFeed.updateAnswer(ethUsdUpdatedPrice); // 1 ETH = $18

        uint256 userHealthFactor = engine.getHealthFactor(USER);

        ERC20Mock(weth).mint(liquidator, collateralToCover);
        vm.startPrank(liquidator);
        ERC20Mock(weth).approve(address(engine), collateralToCover);
        engine.depositCollateralAndMintDsc(weth, collateralToCover, amountToMint);
        dsc.approve(address(engine), amountToMint);
        engine.liquidate(weth, USER, amountToMint);
        vm.stopPrank();
        _;
    }

    function testLiquidationPayoutIsCorrect() public liquidated {
        uint256 liquidatorWethBalance = ERC20Mock(weth).balanceOf(liquidator);
        uint256 getTokenInUsd = engine.getTokenAmountFromUsd(weth, amountToMint);
        uint256 liquidatorBonus = (engine.getTokenAmountFromUsd(weth, amountToMint) / engine.getLiquidationBonus());
        uint256 expectedWeth = getTokenInUsd + liquidatorBonus;
        uint256 userWethBalance = ERC20Mock(weth).balanceOf(USER);
        uint256 hardCodedValue = 6111111111111111110;
        console.log("Liquidator Weth-Balance:", liquidatorWethBalance);
        console.log("User Weth-Balance:", userWethBalance);
        console.log("Expected-Weth:", expectedWeth);
        console.log("TokenInUsd(weth, 100ether):", getTokenInUsd);
        assertEq(expectedWeth, liquidatorWethBalance);
        assertEq(hardCodedValue, liquidatorWethBalance);
    }

    function testUserStillHasSomeEthAfterLiquidation() public liquidated {
        //Calculating how much Weth USER lost
        uint256 amountLiquidated = engine.getTokenAmountFromUsd(weth, amountToMint)
            + (engine.getTokenAmountFromUsd(weth, amountToMint) / engine.getLiquidationBonus());
        uint256 liquidatedAmountInUsd = engine.getUsdValue(weth, amountLiquidated);
        uint256 expectedUserCollateralValueInUsd = engine.getUsdValue(weth, AMOUNT_COLLATERAL) - (liquidatedAmountInUsd);
        console.log("Liquidated Amount In USD:", liquidatedAmountInUsd);
        (, uint256 userCollateralValueInUsd) = engine.getAccountInformation(USER);
        uint256 hardCodedValue = 70000000000000000020;
        assertEq(userCollateralValueInUsd, expectedUserCollateralValueInUsd);
        assertEq(userCollateralValueInUsd, hardCodedValue);
    }

    function testLiquidatorTakesUserDebt() public liquidated {
        (uint256 liquidatorDscMinted,) = engine.getAccountInformation(liquidator);
        assertEq(liquidatorDscMinted, amountToMint);
    }

    function testUserHasNoMoreDebt() public liquidated {
        (uint256 userDscMintedBalance,) = engine.getAccountInformation(USER);
        uint256 expectedUserDscBalance = 0;
        assertEq(userDscMintedBalance, expectedUserDscBalance);
    }

    /////////////////////////////////
    // View & Pure Function Tests //
    ////////////////////////////////

    function testGetDscMinted() public depositedCollateralAndMintedDsc {
        uint256 dscMinted = engine.getDscMinted(USER);
        uint256 expectedDscMinted = 100 ether;
        assertEq(expectedDscMinted, dscMinted);
    }

    function testGetBalanceOf() public {
        uint256 expectedBalance = engine.balanceOf(weth, USER);
        assertEq(STARTING_ERC20_BALANCE, expectedBalance);
    }

    function testGetPrecision() public {
        uint256 expectedPrecision = engine.getPrecision();
        assertEq(expectedPrecision, PRECISION);
    }

    function testAdditionalFeedPrecision() public {
        uint256 expectedAdditionalFeedPrecision = engine.getAdditionalFeedPrecision();
        assertEq(expectedAdditionalFeedPrecision, ADDITIONAL_FEED_PRECISION);
    }

    function testLiquidationThreshold() public {
        uint256 expectedLiquidationThreshold = engine.getLiquidationThreshold();
        assertEq(expectedLiquidationThreshold, LIQUIDATION_THRESHOLD);
    }

    function testLiquidationBonus() public {
        uint256 expectedLiquidationBonus = engine.getLiquidationBonus();
        assertEq(expectedLiquidationBonus, LIQUIDATION_BONUS);
    }

    function testLiquidationPrecision() public {
        uint256 expecetdLiquidationPrecision = engine.getLiquidationPrecision();
        assertEq(expecetdLiquidationPrecision, LIQUIDATION_PRECISION);
    }

    function testMinimumHealthFactor() public {
        uint256 expectedMinimumHealthFacor = engine.getMinHealthFactor();
        assertEq(expectedMinimumHealthFacor, MIN_HEALTH_FACTOR);
    }

    function testHealthFactor() public {
        uint256 expectedHealthFactor = engine.getHealthFactor(USER);
        uint256 hardCodedValue = 115792089237316195423570985008687907853269984665640564039457584007913129639935;
        assertEq(hardCodedValue, expectedHealthFactor);
    }

    function testGetCollateralTokensPriceFeed() public {
        address priceFeed = engine.getCollateralTokenPriceFeed(weth);
        assertEq(priceFeed, ethUsdPriceFeed);
    }

    function testGetDsc() public {
        address getDscAdress = engine.getDsc();
        assertEq(getDscAdress, address(dsc));
    }

    function testGetCollateralTokens() public {
        address[] memory collateralTokens = engine.getCollateralTokens();
        assertEq(collateralTokens[0], weth);
    }
}

