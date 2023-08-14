// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

library Math {
    function _sqrt(uint256 y) internal returns (uint256 z) {
        if (y < 4) {
            z = 1;
        } else {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        }
    }

    function _min(uint256 x, uint256 y) internal pure returns (uint256) {
        return x < y ? x : y;
    }
}
