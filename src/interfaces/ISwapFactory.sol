// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface ISwapFactory {
    function feeCollector() external returns (address);
    function getPair(address t0, address t1) external returns (address);
    function deployPair(address tokenA, address tokenB) external returns (address);
}
