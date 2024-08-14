// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { ISovereignPool } from "@valantis-core/pools/interfaces/ISovereignPool.sol";

import { CPLM } from "../CPLM.sol";

contract DefaultDeployer {
  /************************************************
   *  CUSTOM ERRORS
   ***********************************************/

  error DefaultDeployer__deploy_customSwapFeeModuleNotAllowed();
  error DefaultDeployer__deploy_zeroDefaultSwapFeeNotAllowed();

  /************************************************
   *  EVENTS
   ***********************************************/

  event CPLMDefaultDeployment(address pool, address alm);

  /************************************************
   *  EXTERNAL FUNCTIONS
   ***********************************************/

  /**
        @notice Helper function to deploy a CPLM instance on top of an existing Sovereign Pool.
                It only supports Sovereign Pools with a non-zero constant swap fee, similarly to UniV2 pools.
        @param _pool Address of Sovereign Pool, assumed to already be deployed.
        @dev   It is assumed that `_pool` has this contract's address as its Pool Manager.
        @return alm Address of CPLM deployment.
    */
  function deploy(address _pool) external returns (address alm) {
    ISovereignPool pool = ISovereignPool(_pool);

    // Pool cannot have a custom Swap Fee Module nor a non-zero default fee
    if (pool.swapFeeModule() != address(0)) revert DefaultDeployer__deploy_customSwapFeeModuleNotAllowed();
    if (pool.defaultSwapFeeBips() == 0) revert DefaultDeployer__deploy_zeroDefaultSwapFeeNotAllowed();

    alm = address(new CPLM(_pool));

    // It is assumed that this contract is `poolManager`
    pool.setALM(alm);

    // `poolManager` reset, in order to yield an immutable pool
    pool.setPoolManager(address(0));

    emit CPLMDefaultDeployment(_pool, alm);
  }
}
