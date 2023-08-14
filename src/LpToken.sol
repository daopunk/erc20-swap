// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {ERC20} from "@openzeppelin/token/ERC20/ERC20.sol";

contract LpToken is ERC20 {
    constructor() ERC20("LP Token", "LPT") {}

    function _mint(address account, uint256 amount) internal override {
        _beforeTokenTransfer(address(0), account, amount);

        _totalSupply += amount;
        unchecked {
            _balances[account] += amount;
        }
        emit Transfer(address(0), account, amount);

        _afterTokenTransfer(address(0), account, amount);
    }
}
