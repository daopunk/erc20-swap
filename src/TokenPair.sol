// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {ReentracyGuard} from "@openzeppelin/security/ReentracyGuard.sol";
import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";

contract TokenPair {
    using SafeERC20 for IERC20;

    address public t0;
    address public t1;

    function initialize(address _t0, address _t1) external {
        require(t0 == address(0), "Initialized");
        t0 = _t0;
        t1 = _t1;
    }
}
