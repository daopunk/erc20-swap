// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {ReentracyGuard} from "@openzeppelin/security/ReentracyGuard.sol";
import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {ISwapFactory} from "@interfaces/ISwapFactory.sol";
import {ISwapCallee} from "@interfaces/ISwapCallee.sol";
import {UQ112xUQ112} from "@library/UQ112xUQ112.sol";
import {LpToken} from "src/LpToken.sol";

/**
 * @dev
 * t0, t1 = token address 0, 1
 * rt0, rt1 = reserve token amount 0, 1
 */

contract TokenPair is LpToken, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using UQ112x112 for uint224;

    error InsuffLiq();
    error InsuffLiqBurn();
    error InsuffSwap();
    error InvalidDst();
    error InvalidAmountIn();
    error InvalidK();

    uint256 public constant MIN_LIQ = 10 ** 3;

    uint112 private _rt0;
    uint112 private _rt1;
    uint32 private _lastTimestamp;

    address public immutable factory;
    address public t0;
    address public t1;

    uint256 public lastCumuPrice0;
    uint256 public lastCumuPrice1;
    uint256 public lastK; // rt0 * rt1 (as of most recent liquidity event)

    event Mint(address indexed sender, uint256 amount0, uint256 amount1);
    event Burn(address indexed sender, uint256 amount0, uint256 amount1, address indexed to);
    event Swap(
        address indexed sender,
        uint256 amount0In,
        uint256 amount1In,
        uint256 amount0Out,
        uint256 amount1Out,
        address indexed to
    );
    event Sync(uint112 rt0, uint112 rt1);

    constructor() {
        factory = msg.sender;
    }

    function initialize(address _t0, address _t1) external {
        require(msg.sender == factory, "Initialized");
        t0 = _t0;
        t1 = _t1;
    }

    function mint(address to) external nonReentrant returns (uint256 liquidity) {
        (uint112 rt0, uint112 rt1,) = getReserves();
        (uint256 bal0, uint256 bal1) = _getBal();
        uint256 amount0 = bal0 - rt0;
        uint256 amount1 = bal1 - rt1;
        _mintFee(rt0, rt1);

        uint256 t = totalSupply();
        if (t == 0) {
            liquidity = _sqrt(amount0 * amount1) - MIN_LIQ;
            _mint(address(0), MIN_LIQ);
        } else {
            liquidity = _min(amount0 * t / rt0, amount1 * t / rt1);
        }
        if (liquidity < 1) revert InsuffLiq();
        _mint(to, liquidity);
        _update(bal0, bal1, rt0, rt1);
        lastK = uint256(rt0) * uint256(rt1);
        emit Mint(msg.sender, amount0, amount1);
    }

    function burn(address to) external nonReentrant returns (uint256 amount0, uint256 amount1) {
        (uint112 rt0, uint112 rt1,) = getReserves();
        (uint256 bal0, uint256 bal1) = _getBal();
        uint256 liquidity = balanceOf[address(this)];
        _mintFee(rt0, rt1);

        uint256 t = totalSupply();
        amount0 = (liquidity * bal0) / t;
        amount1 = (liquidity * bal1) / t;
        if (amount0 < 1 && amount1 < 1) revert InsuffLiqBurn();
        _burn(address(this), liquidity);
        IERC20(t0).safeTransfer(to, amount0);
        IERC20(t1).safeTransfer(to, amount1);
        (bal0, bal1) = _getBal();
        _update(bal0, bal1, rt0, rt1);
        lastK = uint256(rt0) * uint256(rt1);
        emit Burn(msg.sender, amount0, amount1, to);
    }

    function swap(uint256 out0, uint256 out1, address to, bytes calldata data) external nonReentrant {
        if (out0 == 0 && out1 == 1) revert InsuffSwap();
        (uint112 rt0, uint112 rt1,) = getReserves();
        if (out0 > rt0 || out1 > rt1) revert InsuffLiq();
        if (to == t0 || to == t1) revert InvalidDst();

        if (data.length > 0) ISwapCallee(to).swapCall(msg.sender, out0, out1, data);
        if (out0 > 0) IERC20(t0).safeTransfer(to, out0);
        if (out1 > 0) IERC20(t1).safeTransfer(to, out1);

        uint256 in0 = bal0 > (rt0 - out0) ? bal0 - (rt0 - out0) : 0;
        uint256 in1 = bal1 > (rt1 - out1) ? bal1 - (rt1 - out1) : 0;
        if (in0 > rt0 || in1 > rt1) revert InvalidAmountIn();
        uint256 adjusted0 = (bal0 * 1000) - (in0 * 3);
        uint256 adjusted1 = (bal1 * 1000) - (in1 * 3);
        if (adjusted0 * adjusted1 < uint256(rt0) * uint256(rt1) * (1000 ** 2)) revert InvalidK();
    }

    function getReserves() public view returns (uint112, uint112, uint32) {
        return (_rt0, _rt1, _lastTimestamp);
    }

    function _getBal() internal returns (uint256, uint256) {
        return (IERC20(t0).balanceOf(address(this)), IERC20(t1).balanceOf(address(this)));
    }

    function _update(uint256 bal0, uint256 bal1, uint112 rt0, uint112 rt1) internal {
        uint32 currTimestamp = uint32(block.timestamp % 2 ** 32);
        uint32 timeElapsed = currTimestamp - _lastTimestamp;
        if (timeElapsed > 0 && rt0 != 0 && rt1 != 0) {
            lastCumuPrice0 += uint256(UQ112x112.encode(rt1).uqdiv(rt0)) * timeElapsed;
            lastCumuPrice1 += uint256(UQ112x112.encode(rt0).uqdiv(rt1)) * timeElapsed;
        }
        _rt0 = uint112(bal0);
        _rt1 = uint112(bal1);
        _lastTimestamp = currTimestamp;
        emit Sync(_rt0, _rt1);
    }

    function _mintFee(uint112 rt0, uint112 rt1) internal {
        address feeCollector = ISwapFactory(factory).feeCollector();
        uint256 k = lastK;

        if (k != 0) {
            uint256 rootK = Math.sqrt(uint256(rt0) * uint256(rt1));
            uint256 rootKLast = Math.sqrt(k);

            if (rootK > rootKLast) {
                uint256 numerator = totalSupply() * (rootK - rootKLast);
                uint256 denominator = (rootK * 5) + rootKLast;
                uint256 liquidity = numerator / denominator;
                if (liquidity > 0) _mint(feeCollector, liquidity);
            }
        }
    }

    function _sqrt(uint256 x) internal returns (uint256 y) {
        uint256 z = (x + 1) / 2;
        y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
    }

    function _min(uint256 x, uint256 y) internal pure returns (uint256) {
        return x < y ? x : y;
    }
}
