// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import { ISovereignALM } from "@valantis-core/ALM/interfaces/ISovereignALM.sol";
import { ALMLiquidityQuoteInput, ALMLiquidityQuote } from "@valantis-core/ALM/structs/SovereignALMStructs.sol";
import { ISovereignPool } from "@valantis-core/pools/interfaces/ISovereignPool.sol";
import { SovereignPool } from "@valantis-core/pools/SovereignPool.sol";

contract CPLM is ISovereignALM, ERC20, ReentrancyGuard {
  using SafeERC20 for IERC20;

  /************************************************
   *  ERRORS
   ***********************************************/

  error CPLM__onlyPool();
  error CPLM__deadlineExpired();
  error CPLM__priceOutOfRange();

  /************************************************
   *  CONSTANTS
   ***********************************************/

  uint256 public constant MINIMUM_LIQUIDITY = 1e6;

  /************************************************
   *  STORAGE
   ***********************************************/

  SovereignPool public pool;

  /************************************************
   *  CONSTRUCTOR
   ***********************************************/
  constructor(string memory _name, string memory _symbol, SovereignPool _pool) ERC20(_name, _symbol) {
    pool = _pool;
  }

  /************************************************
   *  MODIFIERS
   ***********************************************/

  modifier onlyPool() {
    if (msg.sender != address(pool)) {
      revert CPLM__onlyPool();
    }
    _;
  }

  /************************************************
   *  INTERNAL FUNCTIONS
   ***********************************************/

  function _checkPriceRange(uint256 _priceX192Lower, uint256 _priceX192Upper) internal view {
    uint256 priceX192 = getPriceX192();

    if (priceX192 < _priceX192Lower && priceX192 > _priceX192Upper) {
      revert CPLM__priceOutOfRange();
    }
  }

  function _checkDeadline(uint256 _deadline) internal view {
    if (block.timestamp > _deadline) {
      revert CPLM__deadlineExpired();
    }
  }

  /************************************************
   *  EXTERNAL FUNCTIONS
   ***********************************************/

  function getPriceX192() public view returns (uint256 priceX192) {
    (uint256 reserve0, uint256 reserve1) = pool.getReserves();
    priceX192 = Math.mulDiv(reserve1, 2 ** 192, reserve0);
  }

  function mint(
    uint256 _shares,
    address _recipient,
    uint256 _deadline,
    uint256 _priceX192Lower,
    uint256 _priceX192Upper,
    bytes memory _verificationContext
  ) external nonReentrant returns (uint256 amount0, uint256 amount1) {
    _checkDeadline(_deadline);

    _checkPriceRange(_priceX192Lower, _priceX192Upper);

    uint256 _totalSupply = totalSupply();

    // First deposit must be donated directly to the pool
    if (_totalSupply == 0) {
      amount0 = IERC20(pool.token0()).balanceOf(address(this));
      amount1 = IERC20(pool.token1()).balanceOf(address(this));

      _mint(address(0x000000000000000000000000000000000000dEaD), MINIMUM_LIQUIDITY);

      // _shares param is ignored for first deposit
      _mint(_recipient, (amount0 * amount1) - MINIMUM_LIQUIDITY);
    } else {
      (uint256 reserve0, uint256 reserve1) = pool.getReserves();

      // Normal deposits are made using onDepositLiquidityCallback
      amount0 = Math.mulDiv(reserve0, _shares, _totalSupply, Math.Rounding.Ceil);
      amount1 = Math.mulDiv(reserve1, _shares, _totalSupply, Math.Rounding.Ceil);

      _mint(_recipient, _shares);

      ISovereignPool(pool).depositLiquidity(amount0, amount1, msg.sender, _verificationContext, abi.encode(msg.sender));
    }
  }

  function burn(
    uint256 _shares,
    address _recipient,
    uint256 _deadline,
    uint256 _priceX192Lower,
    uint256 _priceX192Upper,
    bytes memory _verificationContext
  ) external nonReentrant returns (uint256 amount0, uint256 amount1) {
    _checkDeadline(_deadline);

    _checkPriceRange(_priceX192Lower, _priceX192Upper);

    (uint256 reserve0, uint256 reserve1) = pool.getReserves();

    amount0 = Math.mulDiv(reserve0, _shares, totalSupply());
    amount1 = Math.mulDiv(reserve1, _shares, totalSupply());

    _burn(msg.sender, _shares);

    ISovereignPool(pool).withdrawLiquidity(amount0, amount1, msg.sender, _recipient, _verificationContext);
  }

  function onDepositLiquidityCallback(
    uint256 _amount0,
    uint256 _amount1,
    bytes memory _data
  ) external override onlyPool {
    address user = abi.decode(_data, (address));

    if (_amount0 > 0) {
      IERC20(pool.token0()).safeTransferFrom(user, msg.sender, _amount0);
    }

    if (_amount1 > 0) {
      IERC20(pool.token1()).safeTransferFrom(user, msg.sender, _amount1);
    }
  }

  // TODO: add onlyPool if any state modifying function is added
  function onSwapCallback(bool _isZeroToOne, uint256 _amountIn, uint256 _amountOut) external override {}

  // TODO: add onlyPool if any state modifying function is added
  function getLiquidityQuote(
    ALMLiquidityQuoteInput memory _poolInput,
    bytes calldata,
    bytes calldata
  ) external view override returns (ALMLiquidityQuote memory quote) {
    (uint256 reserve0, uint256 reserve1) = pool.getReserves();

    quote.isCallbackOnSwap = false;

    if (_poolInput.isZeroToOne) {
      quote.amountOut = (reserve1 * _poolInput.amountInMinusFee) / (reserve0 + _poolInput.amountInMinusFee);
    } else {
      quote.amountOut = (reserve0 * _poolInput.amountInMinusFee) / (reserve1 + _poolInput.amountInMinusFee);
    }

    quote.amountInFilled = _poolInput.amountInMinusFee;
  }
}
