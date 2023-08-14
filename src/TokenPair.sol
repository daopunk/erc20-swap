// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

contract TokenPair {
    uint256 locked;

    address public t0;
    address public t1;

    modifier lock() {
        require(locked == 0, "Lock on");
        locked = 1;
        _;
        locked = 0;
    }

    function initialize(address t0, address t1) external {}
}
