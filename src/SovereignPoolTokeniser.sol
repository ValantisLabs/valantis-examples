// // SPDX-License-Identifier: UNLICENSED
// pragma solidity ^0.8.19;

// abstract contract SovereignPoolTokeniser is ERC20 {
//     SovereignPool pool;

//     constructor(string calldata name, string calldata _symbol, SovereignPool _pool) ERC20(_name, _symbol) {
//         pool = _pool;
//     }

//     function mint(
//         uint256 _shares,
//         address _recipient,
//         bytes memory _verificationContext
//     ) external returns (uint256 amount0Deposited, uint256 amount1Deposited) {
//         (uint256 reserve0, uint256 reserve1) = pool.getReserves();

//         uint256 _totalSupply = totalSupply();

//         uint256 amount0;
//         uint256 amount1;

//         if (_totalSupply == 0) {
//             _mint(address(0), MINIMUM_LIQUIDITY);
//             shares = shares - MINIMUM_LIQUIDITY;

            
//         } else {
//             amount0 = Math.mulDiv(reserve0, _shares, _totalSupply);
//             amount1 = Math.mulDiv(reserve1, _shares, _totalSupply);
//         }

//         _mint(msg.sender, shares);
//     }

//     function burn(uint256 _shares, address _recipient, bytes memory _verificationContext) external {
//         if (_shares == 0) {
//             require(false);
//         }

//         if (_shares > balanceOf(msg.sender)) {
//             require(false);
//         }

//         (uint256 reserve0, uint256 reserve1) = pool.getReserves();

//         amount0 = Math.mulDiv(reserve0, _shares, totalSupply());
//         amount1 = Math.mulDiv(reserve1, _shares, totalSupply());

//         _burn(msg.sender, shares);

//         ISovereignPool(pool).withdrawLiquidity(_amount0, _amount1, msg.sender, _recipient, _verificationContext);
//     }

//     function onDepositLiquidityCallback(
//         uint256 _amount0,
//         uint256 _amount1,
//         bytes memory _data
//     ) external override onlyPool {
//         address user = abi.decode(_data, (address));

//         (address token0, address token1) = (ISovereignPool(pool).token0(), ISovereignPool(pool).token1());

//         if (_amount0 > 0) {
//             IERC20(token0).safeTransferFrom(user, msg.sender, _amount0);
//         }

//         if (_amount1 > 0) {
//             IERC20(token1).safeTransferFrom(user, msg.sender, _amount1);
//         }
//     }
// }
