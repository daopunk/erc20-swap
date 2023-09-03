// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {TestHelper} from "test/TestHelper.t.sol";

contract TokenPair is TestHelper {
    function testSetup() public {
        (address t0, address t1) = tokenA < tokenB ? ((tokenA), tokenB) : (tokenB, (tokenA));

        assertEq(feeCollector, swapFactory.feeCollector());
        assertEq(address(tokenPair), swapFactory.getPair(t0, t1));
    }
}
