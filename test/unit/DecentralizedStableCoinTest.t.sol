//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";

contract DecentralizedStableCoinTest is Test {
    DecentralizedStableCoin dsc;
    address weth;

    address public user = address(this);
    address public zeroAddress = address(0); // test if revert on zero address

    function setUp() external {
        dsc = new DecentralizedStableCoin();
    }

    function testRevertsIfBurnAmountIsZero() public {
        vm.startPrank(user);
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin__AmountMustBeMoreThanZero.selector);
        dsc.burn(0);
    }

    function testRevertsIfBurnAmountIsLessThanBalance() public {
        vm.startPrank(user);
        dsc.mint(user, 100);
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin__BurnAmountExceedsBalance.selector);
        dsc.burn(101);
    }

    function testMintFunctionRevertsOnZeroAddress() public {
        vm.startPrank(user);
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin__NotZeroAddress.selector);
        dsc.mint(zeroAddress, 100);
    }

    function testMintBalanceMustBeMoreThanZero() public {
        vm.startPrank(user);
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin__AmountMustBeMoreThanZero.selector);
        dsc.mint(user, 0);
        vm.stopPrank();
    }
}