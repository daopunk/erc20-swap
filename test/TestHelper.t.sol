// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {LpToken} from "src/LpToken.sol";
import {SwapFactory} from "src/SwapFactory.sol";
import {TokenPair} from "src/TokenPair.sol";
import {TestToken} from "src/utils/TestToken.sol";

contract TestHelper is Test {
    LpToken public lpToken;
    SwapFactory public swapFactory;
    TokenPair public tokenPair;
    address public tokenA;
    address public tokenB;

    address public feeCollector = address(0xfeeC011ec);

    function setUp() public {
        tokenA = address(new TestToken("test0", "TST0"));
        tokenB = address(new TestToken("test1", "TST1"));
        lpToken = new LpToken();
        swapFactory = new SwapFactory(feeCollector);
        tokenPair = TokenPair(swapFactory.deployPair(tokenA, tokenB));
    }
}
