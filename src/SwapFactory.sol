// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {ITokenPair} from "@interfaces/ITokenPair.sol";
import {Ownable2Step} from "@openzeppelin/access/Ownable2Step.sol";

contract SwapFactory is Ownable2Step {
    error IndeticalTokens();
    error ZeroAddress();
    error PairExists();

    address public feeCollector;

    mapping(address t0 => mapping(address t1 => address pair)) public getPair;

    event PairCreated(address indexed t0, address indexed t1, address pair);

    constructor(address _feeCollector) {
        require(_feeCollector != address(0));
        feeCollector = _feeCollector;
    }

    function deployPair(address tokenA, address tokenB) external returns (address pair) {
        if (tokenA == tokenB) revert IndeticalTokens();
        (address t0, address t1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        if (t0 == address(0)) revert ZeroAddress();
        if (getPair[t0][t1] != address(0)) revert PairExists();

        bytes memory bytecode = type(TokenPair).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(t0, t1));
        assembly {
            pair := create2(0, add(bytecode, 0x20), mload(bytecode), salt)
        }
        getPair[t0][t1] = pair;
        ITokenPair(pair).initialize(t0, t1);
        emit PairCreated(t0, t1, pair);
    }
}
