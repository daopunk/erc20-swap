// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {ERC20} from "@openzeppelin/token/ERC20/ERC20.sol";

contract LpToken is ERC20 {
    constructor() ERC20("LP Token", "LPT") {}
}
