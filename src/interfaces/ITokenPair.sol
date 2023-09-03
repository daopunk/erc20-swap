// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface ITokenPair {
    error InsuffLiq();
    error InsuffLiqBurn();
    error InsuffSwap();
    error InvalidDst();
    error InvalidAmount();
    error InvalidK();
    error InvalidToken();
    error NotAuth();
    error Initialized();

    function initialize(address t0, address t1) external;
}
