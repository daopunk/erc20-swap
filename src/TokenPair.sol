// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {ReentrancyGuard} from "@openzeppelin/security/ReentrancyGuard.sol";
import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {IERC3156FlashBorrower} from "@openzeppelin/interfaces/IERC3156FlashBorrower.sol";
import {IERC3156FlashLender} from "@openzeppelin/interfaces/IERC3156FlashLender.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {ISwapFactory} from "@interfaces/ISwapFactory.sol";
import {ISwapCallee} from "@interfaces/ISwapCallee.sol";
import {ITokenPair} from "@interfaces/ITokenPair.sol";
import {UQ112x112} from "@library/UQ112x112.sol";
import {Math} from "@library/Math.sol";
import {LpToken} from "src/LpToken.sol";
import {FixedPointMathLib} from "@solady/utils/FixedPointMathLib.sol";

contract TokenPair is ITokenPair, IERC3156FlashLender, LpToken, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using UQ112x112 for uint224;

    uint256 public constant MIN_LIQ = 10 ** 3;
    uint256 public constant FEE = 1; //  1 == 0.01 % for flashloan
    bytes32 public constant CALLBACK_SUCCESS = keccak256("ERC3156FlashBorrower.onFlashLoan");

    address public immutable factory;

    address public token0;
    address public token1;

    uint112 private _reserveToken0;
    uint112 private _reserveToken1;
    uint32 private _lastTimestamp;

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

    modifier validToken(address token) {
        if (token != token0 && token != token1) revert InvalidToken();
        _;
    }

    modifier initializer() {
        if (token0 != address(0)) revert Initialized();
        if (msg.sender != factory) revert NotAuth();
        _;
    }

    /**
     * @dev initialize immutable token pair addresses
     */
    function initialize(address _t0, address _t1) external initializer {
        token0 = _t0;
        token1 = _t1;
    }

    /**
     * @dev max amount of token reserve
     */
    function maxFlashLoan(address token) external view validToken(token) returns (uint256) {
        return type(uint256).max - IERC20(token).balanceOf(address(this));
    }

    /**
     * @dev fee charged on principal loan
     */
    function flashFee(address token, uint256 amount) external view validToken(token) returns (uint256) {
        return _flashFee(amount);
    }

    /**
     * @dev initiate a flash loan
     */
    function flashLoan(IERC3156FlashBorrower receiver, address token, uint256 amount, bytes calldata data)
        external
        validToken(token)
        returns (bool)
    {
        if (amount == 0) revert InvalidAmount();
        uint256 fee = _flashFee(amount);
        IERC20(token).transfer(address(receiver), amount);
        require(
            receiver.onFlashLoan(msg.sender, token, amount, fee, data) == CALLBACK_SUCCESS,
            "FlashMinter: Callback failed"
        );
        require(IERC20(token).transferFrom(address(receiver), address(this), amount + fee), "FlashLender: Repay failed");
        (uint256 bal0, uint256 bal1) = _getBal();
        (uint112 rt0, uint112 rt1,) = getReserves();
        _update(bal0, bal1, rt0, rt1);
        return true;
    }

    function mint(address to) external nonReentrant returns (uint256 liquidity) {
        (uint112 rt0, uint112 rt1,) = getReserves();
        (uint256 bal0, uint256 bal1) = _getBal();
        uint256 amount0 = bal0 - rt0;
        uint256 amount1 = bal1 - rt1;
        _mintFee(rt0, rt1);

        uint256 t = totalSupply();
        if (t == 0) {
            liquidity = Math._sqrt(amount0 * amount1) - MIN_LIQ;
            _mint(address(0), MIN_LIQ);
        } else {
            liquidity = Math._min(amount0 * t / rt0, amount1 * t / rt1);
        }
        if (liquidity < 1) revert InsuffLiq();
        _mint(to, liquidity);
        _update(bal0, bal1, rt0, rt1);
        lastK = uint256(_reserveToken0) * uint256(_reserveToken1);
        emit Mint(msg.sender, amount0, amount1);
    }

    function burn(address to) external nonReentrant returns (uint256 amount0, uint256 amount1) {
        (uint112 rt0, uint112 rt1,) = getReserves();
        (uint256 bal0, uint256 bal1) = _getBal();
        uint256 liquidity = balanceOf(address(this));
        _mintFee(rt0, rt1);

        uint256 t = totalSupply();
        amount0 = (liquidity * bal0) / t;
        amount1 = (liquidity * bal1) / t;
        if (amount0 < 1 && amount1 < 1) revert InsuffLiqBurn();

        _burn(address(this), liquidity);
        IERC20(token0).safeTransfer(to, amount0);
        IERC20(token1).safeTransfer(to, amount1);

        (bal0, bal1) = _getBal();
        _update(bal0, bal1, rt0, rt1);
        lastK = uint256(_reserveToken0) * uint256(_reserveToken1);
        emit Burn(msg.sender, amount0, amount1, to);
    }

    function swap(uint256 amountOut0, uint256 amountOut1, address to) external nonReentrant {
        if (amountOut0 == 0 && amountOut1 == 0) revert InsuffSwap();
        (uint112 rt0, uint112 rt1,) = getReserves();

        if (amountOut0 > rt0 || amountOut1 > rt1) revert InsuffLiq();

        {
            address t0 = token0;
            address t1 = token1;
            if (to == t0 || to == t1) revert InvalidDst();
            // optimistic transfer
            if (amountOut0 > 0) IERC20(t0).safeTransfer(to, amountOut0);
            if (amountOut1 > 0) IERC20(t1).safeTransfer(to, amountOut1);
        }

        // update balances
        (uint256 bal0, uint256 bal1) = _getBal();

        // calc input amount, enforce amount in
        uint256 amountIn0 = bal0 > (rt0 - amountOut0) ? bal0 - (rt0 - amountOut0) : 0;
        uint256 amountIn1 = bal1 > (rt1 - amountOut1) ? bal1 - (rt1 - amountOut1) : 0;
        if (amountIn0 > rt0 || amountIn1 > rt1) revert InvalidAmount();
        {
            // adjust balances, enforce invariant
            uint256 adjusted0 = (bal0 * 1000) - (amountIn0 * 3);
            uint256 adjusted1 = (bal1 * 1000) - (amountIn1 * 3);
            if (adjusted0 * adjusted1 < uint256(rt0) * uint256(rt1) * (1000 ** 2)) revert InvalidK();
        }
        // update reserves, emit event
        _update(bal0, bal1, rt0, rt1);
        emit Swap(msg.sender, amountIn0, amountIn1, amountOut0, amountOut0, to);
    }

    /**
     * @dev update reserves
     */
    function sync() external nonReentrant {
        (uint256 bal0, uint256 bal1) = _getBal();
        _update(bal0, bal1, _reserveToken0, _reserveToken1);
    }

    function getReserves() public view returns (uint112, uint112, uint32) {
        return (_reserveToken0, _reserveToken1, _lastTimestamp);
    }

    function _getBal() internal view returns (uint256, uint256) {
        return (IERC20(token0).balanceOf(address(this)), IERC20(token1).balanceOf(address(this)));
    }

    function _update(uint256 bal0, uint256 bal1, uint112 rt0, uint112 rt1) internal {
        uint32 currTimestamp = uint32(block.timestamp % 2 ** 32);
        uint32 timeElapsed = currTimestamp - _lastTimestamp;

        if (timeElapsed > 0 && rt0 != 0 && rt1 != 0) {
            lastCumuPrice0 += uint256(UQ112x112.encode(rt1).uqdiv(rt0)) * timeElapsed;
            lastCumuPrice1 += uint256(UQ112x112.encode(rt0).uqdiv(rt1)) * timeElapsed;
        }
        _reserveToken0 = uint112(bal0);
        _reserveToken1 = uint112(bal1);
        _lastTimestamp = currTimestamp;
        emit Sync(_reserveToken0, _reserveToken1);
    }

    function _mintFee(uint112 rt0, uint112 rt1) internal {
        address feeCollector = ISwapFactory(factory).feeCollector();
        uint256 k = lastK;

        if (k != 0) {
            // calc sqroot of reserves / calc sqroot of last K
            uint256 rootK = Math._sqrt(uint256(rt0) * uint256(rt1));
            uint256 rootKLast = Math._sqrt(k);

            if (rootK > rootKLast) {
                uint256 numerator = totalSupply() * (rootK - rootKLast);
                uint256 denominator = (rootK * 5) + rootKLast;
                uint256 liquidity = numerator / denominator;

                // mint fee to fee collector
                if (liquidity > 0) _mint(feeCollector, liquidity);
            }
        }
    }

    /**
     * @dev fee charged on principal loan
     */
    function _flashFee(uint256 amount) internal pure returns (uint256 fee) {
        fee = amount * FEE / 10000;
    }
}
