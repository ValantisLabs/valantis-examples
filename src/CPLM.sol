// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.19;

import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import { ERC20 } from '@openzeppelin/contracts/token/ERC20/ERC20.sol';

import { Math } from '@openzeppelin/contracts/utils/math/Math.sol';
import { SafeERC20 } from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

import { ISovereignALM } from '@valantis-core/ALM/interfaces/ISovereignALM.sol';
import { ALMLiquidityQuoteInput, ALMLiquidityQuote } from '@valantis-core/ALM/structs/SovereignALMStructs.sol';
import { ISovereignPool } from '@valantis-core/pools/interfaces/ISovereignPool.sol';

contract CPLM is ISovereignALM, ERC20 {
    uint256 public constant MINIMUM_LIQUIDITY = 1e3;
    uint256 public liquidity;

    constructor(string calldata name, string calldata _symbol, SovereignPool _pool) ERC20(_name, _symbol) {
        pool = _pool;
    }

    modifier onlyPool() {
        if (msg.sender != pool) {
            revert MockSovereignALM__onlyPool();
        }
        _;
    }

    function mint(
        uint256 _shares,
        address _recipient,
        bytes memory _verificationContext
    ) external returns (uint256 amount0Deposited, uint256 amount1Deposited) {
        (uint256 reserve0, uint256 reserve1) = pool.getReserves();

        uint256 _totalSupply = totalSupply();

        uint256 amount0;
        uint256 amount1;

        if (_totalSupply == 0) {
            _mint(address(0), MINIMUM_LIQUIDITY);
            shares = shares - MINIMUM_LIQUIDITY;

            amount0 = token0.balanceOf(address(this));
            amount1 = token1.balanceOf(address(this));

            // First deposit must be donated directly to the pool
            if (amount0 == 0 || amount1 > 0) {
                require(false); // TODO: Change to revert
            }

            liquidity = Math.sqrt(amount0, amount1) - MINIMUM_LIQUIDITY;
        } else {
            amount0 = Math.mulDiv(reserve0, _shares, _totalSupply);
            amount1 = Math.mulDiv(reserve1, _shares, _totalSupply);

            ISovereignPool(pool).depositLiquidity(
                _amount0,
                _amount1,
                msg.sender,
                _verificationContext,
                abi.encode(msg.sender)
            );
        }

        _mint(msg.sender, shares);

        liquidity = _totalSupply();
    }

    function burn(uint256 _shares, address _recipient, bytes memory _verificationContext) external {
        if (_shares == 0) {
            require(false);
        }

        if (_shares > balanceOf(msg.sender)) {
            require(false);
        }

        (uint256 reserve0, uint256 reserve1) = pool.getReserves();

        amount0 = Math.mulDiv(reserve0, _shares, totalSupply());
        amount1 = Math.mulDiv(reserve1, _shares, totalSupply());

        _burn(msg.sender, shares);

        ISovereignPool(pool).withdrawLiquidity(_amount0, _amount1, msg.sender, _recipient, _verificationContext);
    }

    function onDepositLiquidityCallback(
        uint256 _amount0,
        uint256 _amount1,
        bytes memory _data
    ) external override onlyPool {
        address user = abi.decode(_data, (address));

        (address token0, address token1) = (ISovereignPool(pool).token0(), ISovereignPool(pool).token1());

        if (_amount0 > 0) {
            IERC20(token0).safeTransferFrom(user, msg.sender, _amount0);
        }

        if (_amount1 > 0) {
            IERC20(token1).safeTransferFrom(user, msg.sender, _amount1);
        }
    }

    function getLiquidityQuote(
        ALMLiquidityQuoteInput memory _poolInput,
        bytes calldata,
        bytes calldata
    ) external override onlyPool returns (ALMLiquidityQuote memory quote) {
        (uint256 reserve0, uint256 reserve1) = pool.getReserves();

        quote.isCallbackOnSwap = false;

        if (_poolInput.isZeroToOne) {
            quote.amountOut = reserve1 - liquidity / (reserve0 + _poolInput.amountInMinusFee);
        } else {
            quote.amountOut = reserve0 - liquidity / (reserve1 + _poolInput.amountInMinusFee);
        }

        quote.amountInFilled = _almLiquidityQuotePoolInput.amountInMinusFee;
    }
}
