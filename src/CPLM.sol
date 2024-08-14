// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import { ISovereignALM } from "@valantis-core/ALM/interfaces/ISovereignALM.sol";
import { ALMLiquidityQuoteInput, ALMLiquidityQuote } from "@valantis-core/ALM/structs/SovereignALMStructs.sol";
import { ISovereignPool } from "@valantis-core/pools/interfaces/ISovereignPool.sol";

/**
  @title Constant Product Liquidity Module.
  @dev UniswapV2 style constant product,
       implemented as a Valantis Sovereign Liquidity Module.
 */
contract CPLM is ISovereignALM, ERC20, ReentrancyGuard {
  using SafeERC20 for IERC20;

  /************************************************
   *  ERRORS
   ***********************************************/

  error CPLM__deadlineExpired();
  error CPLM__onlyPool();
  error CPLM__priceOutOfRange();
  error CPLM__constructor_customSovereignVaultNotAllowed();
  error CPLM__constructor_invalidPool();
  error CPLM__burn_bothAmountsZero();
  error CPLM__burn_insufficientToken0Withdrawn();
  error CPLM__burn_insufficientToken1Withdrawn();
  error CPLM__burn_zeroShares();
  error CPLM__mint_insufficientToken0Deposited();
  error CPLM__mint_insufficientToken1Deposited();
  error CPLM__mint_invalidRecipient();
  error CPLM__mint_zeroShares();

  /************************************************
   *  CONSTANTS
   ***********************************************/

  uint256 public constant MINIMUM_LIQUIDITY = 1000;

  /************************************************
   *  IMMUTABLES
   ***********************************************/

  /**
    @dev SovereignPool is both the entry point contract for swaps (via `swap` function),
         and the contract in which token0 and token1 balances should be stored.
   */
  ISovereignPool public immutable POOL;

  /************************************************
   *  CONSTRUCTOR
   ***********************************************/

  constructor(string memory _name, string memory _symbol, address _pool) ERC20(_name, _symbol) {
    if (_pool == address(0)) revert CPLM__constructor_invalidPool();

    POOL = ISovereignPool(_pool);

    if (POOL.sovereignVault() != _pool) revert CPLM__constructor_customSovereignVaultNotAllowed();
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

  /**
      @notice Deposit liquidity into `POOL` and mint LP tokens.
      @param _shares Amount of LP tokens to mint.
      @param _amount0Min Minimum amount of token0 required.
      @param _amount1Min Minimum amount of token1 required.
      @param _deadline Block timestamp after which this call reverts.
      @param _recipient Address to mint LP tokens for.
      @param _verificationContext Bytes encoded calldata for POOL's Verifier Module, if applicable.
      @return amount0 Amount of token0 deposited.
      @return amount1 Amount of token1 deposited. 
   */
  function deposit(
    uint256 _shares,
    uint256 _amount0Min,
    uint256 _amount1Min,
    uint256 _deadline,
    address _recipient,
    bytes memory _verificationContext
  ) external nonReentrant returns (uint256 amount0, uint256 amount1) {
    _checkDeadline(_deadline);

    if (_recipient == address(0)) revert CPLM__mint_invalidRecipient();

    uint256 totalSupplyCache = totalSupply();
    uint256 sharesToRecipient;
    if (totalSupplyCache == 0) {
      // Minimum token amounts taken as amounts during first deposit
      amount0 = _amount0Min;
      amount1 = _amount1Min;

      _mint(address(1), MINIMUM_LIQUIDITY);

      // _shares param is ignored during first deposit
      sharesToRecipient = Math.sqrt(amount0 * amount1) - MINIMUM_LIQUIDITY;
    } else {
      (uint256 reserve0, uint256 reserve1) = POOL.getReserves();

      // Normal deposits are made using `onDepositLiquidityCallback`
      amount0 = Math.mulDiv(reserve0, _shares, totalSupplyCache, Math.Rounding.Ceil);
      amount1 = Math.mulDiv(reserve1, _shares, totalSupplyCache, Math.Rounding.Ceil);

      if (amount0 < _amount0Min) revert CPLM__mint_insufficientToken0Deposited();
      if (amount1 < _amount1Min) revert CPLM__mint_insufficientToken1Deposited();

      sharesToRecipient = _shares;
    }

    if (sharesToRecipient == 0) revert CPLM__mint_zeroShares();

    _mint(_recipient, sharesToRecipient);

    // Token amounts deposited might differ in case of rebase tokens,
    // so we update these after transfers to `POOL` have been executed
    (amount0, amount1) = POOL.depositLiquidity(
      amount0,
      amount1,
      msg.sender,
      _verificationContext,
      abi.encode(msg.sender)
    );
  }

  /**
      @notice Withdraw liquidity from `POOL` and burn LP tokens.
      @param _shares Amount of LP tokens to burn.
      @param _amount0Min Minimum amount of token0 required for `_recipient`.
      @param _amount1Min Minimum amount of token1 required for `_recipient`.
      @param _deadline Block timestamp after which this call reverts.
      @param _recipient Address to receive token0 and token1 amounts.
      @param _verificationContext Bytes encoded calldata for POOL's Verifier Module, if applicable.
      @return amount0 Amount of token0 withdrawn. WARNING: Potentially innacurate in case token0 is rebase.
      @return amount1 Amount of token1 withdrawn. WARNING: Potentially innacurate in case token1 is rebase.
   */
  function withdraw(
    uint256 _shares,
    uint256 _amount0Min,
    uint256 _amount1Min,
    uint256 _deadline,
    address _recipient,
    bytes memory _verificationContext
  ) external nonReentrant returns (uint256 amount0, uint256 amount1) {
    _checkDeadline(_deadline);

    if (_shares == 0) revert CPLM__burn_zeroShares();

    (uint256 reserve0, uint256 reserve1) = POOL.getReserves();

    uint256 totalSupplyCache = totalSupply();
    amount0 = Math.mulDiv(reserve0, _shares, totalSupplyCache);
    amount1 = Math.mulDiv(reserve1, _shares, totalSupplyCache);

    if (amount0 == 0 && amount1 == 0) revert CPLM__burn_bothAmountsZero();

    // Slippage protection checks
    if (amount0 < _amount0Min) revert CPLM__burn_insufficientToken0Withdrawn();
    if (amount1 < _amount1Min) revert CPLM__burn_insufficientToken1Withdrawn();

    _burn(msg.sender, _shares);

    POOL.withdrawLiquidity(amount0, amount1, msg.sender, _recipient, _verificationContext);
  }

  /**
    @notice Callback to transfer tokens from user into `POOL` during deposits. 
   */
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

  /**
      @notice Swap callback from POOL.
      @param _poolInput Contains fundamental data about the swap. 
      @return quote Quote information that prices tokenIn and tokenOut.
   */
  function getLiquidityQuote(
    ALMLiquidityQuoteInput memory _poolInput,
    bytes calldata /*_externalContext*/,
    bytes calldata /*_verifierData*/
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
  function onSwapCallback(bool /*_isZeroToOne*/, uint256 /*_amountIn*/, uint256 /*_amountOut*/) external override {}

  /************************************************
   *  PRIVATE FUNCTIONS
   ***********************************************/

  function _checkDeadline(uint256 _deadline) private view {
    if (block.timestamp > _deadline) {
      revert CPLM__deadlineExpired();
    }
  }
}
