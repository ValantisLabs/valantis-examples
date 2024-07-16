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

contract CPLM is ISovereignALM, ERC20, ReentrancyGuard {
  using SafeERC20 for IERC20;

  /************************************************
   *  ERRORS
   ***********************************************/

  error CPLM__onlyPool();
  error CPLM__deadlineExpired();
  error CPLM__priceOutOfRange();
  error CPLM__burn_insufficientToken0Withdrawn();
  error CPLM__burn_insufficientToken1Withdrawn();
  error CPLM__mint_insufficientToken0Deposited();
  error CPLM__mint_insufficientToken1Deposited();

  /************************************************
   *  CONSTANTS
   ***********************************************/

  uint256 public constant MINIMUM_LIQUIDITY = 1000;

  /************************************************
   *  IMMUTABLES
   ***********************************************/

  ISovereignPool public immutable POOL;

  /************************************************
   *  CONSTRUCTOR
   ***********************************************/

  constructor(string memory _name, string memory _symbol, address _pool) ERC20(_name, _symbol) {
    POOL = ISovereignPool(_pool);
  }

  /************************************************
   *  MODIFIERS
   ***********************************************/

  modifier onlyPool() {
    if (msg.sender != address(POOL)) {
      revert CPLM__onlyPool();
    }
    _;
  }

  /************************************************
   *  EXTERNAL FUNCTIONS
   ***********************************************/

  function getPriceX192() public view returns (uint256 priceX192) {
    (uint256 reserve0, uint256 reserve1) = POOL.getReserves();
    priceX192 = Math.mulDiv(reserve1, 2 ** 192, reserve0);
  }

  function mint(
    uint256 _shares,
    uint256 _amount0Min,
    uint256 _amount1Min,
    uint256 _deadline,
    address _recipient,
    bytes memory _verificationContext
  ) external nonReentrant returns (uint256 amount0, uint256 amount1) {
    _checkDeadline(_deadline);

    uint256 totalSupplyCache = totalSupply();

    // First deposit must be donated directly to the pool
    if (totalSupplyCache == 0) {
      amount0 = IERC20(POOL.token0()).balanceOf(address(this));
      amount1 = IERC20(POOL.token1()).balanceOf(address(this));

      _mint(address(1), MINIMUM_LIQUIDITY);

      // _shares param is ignored for first deposit
      _mint(_recipient, Math.sqrt(amount0 * amount1) - MINIMUM_LIQUIDITY);
    } else {
      (uint256 reserve0, uint256 reserve1) = POOL.getReserves();

      // Normal deposits are made using onDepositLiquidityCallback
      amount0 = Math.mulDiv(reserve0, _shares, totalSupplyCache, Math.Rounding.Ceil);
      amount1 = Math.mulDiv(reserve1, _shares, totalSupplyCache, Math.Rounding.Ceil);

      _mint(_recipient, _shares);

      (amount0, amount1) = POOL.depositLiquidity(
        amount0,
        amount1,
        msg.sender,
        _verificationContext,
        abi.encode(msg.sender)
      );

      if (amount0 < _amount0Min) revert CPLM__mint_insufficientToken0Deposited();
      if (amount1 < _amount1Min) revert CPLM__mint_insufficientToken1Deposited();
    }
  }

  function burn(
    uint256 _shares,
    uint256 _amount0Min,
    uint256 _amount1Min,
    uint256 _deadline,
    address _recipient,
    bytes memory _verificationContext
  ) external nonReentrant returns (uint256 amount0, uint256 amount1) {
    _checkDeadline(_deadline);

    (uint256 reserve0, uint256 reserve1) = POOL.getReserves();

    uint256 totalSupplyCache = totalSupply();
    amount0 = Math.mulDiv(reserve0, _shares, totalSupplyCache);
    amount1 = Math.mulDiv(reserve1, _shares, totalSupplyCache);

    if (amount0 < _amount0Min) revert CPLM__burn_insufficientToken0Withdrawn();
    if (amount1 < _amount1Min) revert CPLM__burn_insufficientToken1Withdrawn();

    _burn(msg.sender, _shares);

    POOL.withdrawLiquidity(amount0, amount1, msg.sender, _recipient, _verificationContext);
  }

  function onDepositLiquidityCallback(
    uint256 _amount0,
    uint256 _amount1,
    bytes memory _data
  ) external override onlyPool {
    address user = abi.decode(_data, (address));

    if (_amount0 > 0) {
      IERC20(POOL.token0()).safeTransferFrom(user, msg.sender, _amount0);
    }

    if (_amount1 > 0) {
      IERC20(POOL.token1()).safeTransferFrom(user, msg.sender, _amount1);
    }
  }

  // TODO: add onlyPool if any state modifying function is added
  function getLiquidityQuote(
    ALMLiquidityQuoteInput memory _poolInput,
    bytes calldata,
    bytes calldata
  ) external view override returns (ALMLiquidityQuote memory quote) {
    (uint256 reserve0, uint256 reserve1) = POOL.getReserves();

    if (_poolInput.isZeroToOne) {
      quote.amountOut = (reserve1 * _poolInput.amountInMinusFee) / (reserve0 + _poolInput.amountInMinusFee);
    } else {
      quote.amountOut = (reserve0 * _poolInput.amountInMinusFee) / (reserve1 + _poolInput.amountInMinusFee);
    }

    quote.amountInFilled = _poolInput.amountInMinusFee;
  }

  // solhint-disable-next-line no-empty-blocks
  function onSwapCallback(bool _isZeroToOne, uint256 _amountIn, uint256 _amountOut) external override {}

  /************************************************
   *  PRIVATE FUNCTIONS
   ***********************************************/

  function _checkDeadline(uint256 _deadline) private view {
    if (block.timestamp > _deadline) {
      revert CPLM__deadlineExpired();
    }
  }
}
