// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { ISovereignALM } from "@valantis-core/ALM/interfaces/ISovereignALM.sol";
import { ALMLiquidityQuoteInput, ALMLiquidityQuote } from "@valantis-core/ALM/structs/SovereignALMStructs.sol";
import { ISovereignPool } from "@valantis-core/pools/interfaces/ISovereignPool.sol";
import { SovereignPool } from "@valantis-core/pools/SovereignPool.sol";

contract CPLM is ISovereignALM, ERC20 {
    using SafeERC20 for IERC20;

    error CPLM__onlyPool();

    uint256 public constant MINIMUM_LIQUIDITY = 1e3;

    SovereignPool public pool;

    constructor(string memory _name, string memory _symbol, SovereignPool _pool) ERC20(_name, _symbol) {
        pool = _pool;
    }

    modifier onlyPool() {
        if (msg.sender != address(pool)) {
            revert CPLM__onlyPool();
        }
        _;
    }

    function mint(
        uint256 _shares,
        address _recipient,
        bytes memory _verificationContext
    )
        external
        returns (uint256 amount0, uint256 amount1)
    {
        uint256 _totalSupply = totalSupply();

        // First deposit must be donated directly to the pool
        if (_totalSupply == 0) {
            amount0 = IERC20(pool.token0()).balanceOf(address(this));
            amount1 = IERC20(pool.token1()).balanceOf(address(this));

            _mint(address(0), MINIMUM_LIQUIDITY);

            // _shares param is ignored for first deposit
            _mint(_recipient, (amount0 * amount1) - MINIMUM_LIQUIDITY);
        } else {
            (uint256 reserve0, uint256 reserve1) = pool.getReserves();

            // Normal deposits are made using onDepositLiquidityCallback
            amount0 = Math.mulDiv(reserve0, _shares, _totalSupply);
            amount1 = Math.mulDiv(reserve1, _shares, _totalSupply);

            _mint(_recipient, _shares);

            ISovereignPool(pool).depositLiquidity(
                amount0, amount1, msg.sender, _verificationContext, abi.encode(msg.sender)
            );
        }
    }

    function burn(uint256 _shares, address _recipient, bytes memory _verificationContext) external {
        (uint256 reserve0, uint256 reserve1) = pool.getReserves();

        uint256 amount0 = Math.mulDiv(reserve0, _shares, totalSupply());
        uint256 amount1 = Math.mulDiv(reserve1, _shares, totalSupply());

        _burn(msg.sender, _shares);

        ISovereignPool(pool).withdrawLiquidity(amount0, amount1, msg.sender, _recipient, _verificationContext);
    }

    function onDepositLiquidityCallback(
        uint256 _amount0,
        uint256 _amount1,
        bytes memory _data
    )
        external
        override
        onlyPool
    {
        address user = abi.decode(_data, (address));

        if (_amount0 > 0) {
            IERC20(pool.token0()).safeTransferFrom(user, msg.sender, _amount0);
        }

        if (_amount1 > 0) {
            IERC20(pool.token1()).safeTransferFrom(user, msg.sender, _amount1);
        }
    }

    // TODO: add onlyPool if any state modifying function is added
    function onSwapCallback(bool _isZeroToOne, uint256 _amountIn, uint256 _amountOut) external override { }

    // TODO: add onlyPool if any state modifying function is added
    function getLiquidityQuote(
        ALMLiquidityQuoteInput memory _poolInput,
        bytes calldata,
        bytes calldata
    )
        external
        view
        override
        returns (ALMLiquidityQuote memory quote)
    {
        (uint256 reserve0, uint256 reserve1) = pool.getReserves();

        quote.isCallbackOnSwap = false;

        uint256 k = reserve0 * reserve1;

        if (_poolInput.isZeroToOne) {
            quote.amountOut = reserve1 - (k / (reserve0 + _poolInput.amountInMinusFee));
        } else {
            quote.amountOut = reserve0 - (k / (reserve1 + _poolInput.amountInMinusFee));
        }

        quote.amountInFilled = _poolInput.amountInMinusFee;
    }
}
