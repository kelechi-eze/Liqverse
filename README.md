# Liqverse

## Overview

Liqverse is a decentralized Automated Market Maker (AMM) smart contract that enables token swaps and liquidity provisioning. It supports pool creation, liquidity management, token swaps with fees, and read-only analytics.

## Features

* Creation of liquidity pools between two tokens
* Adding and removing liquidity with proportional share management
* Token swapping with constant product formula and slippage protection
* Fee collection and tracking
* Read-only functions for pool and liquidity position queries

## Functions

### Public Functions

* `create-pool (token-a token-b amount-a amount-b)`
  Create a new liquidity pool with initial token deposits.

* `add-liquidity (pool-id token-a token-b amount-a amount-b min-shares)`
  Add liquidity to an existing pool and receive shares.

* `remove-liquidity (pool-id token-a token-b shares min-amount-a min-amount-b)`
  Remove liquidity and withdraw underlying tokens.

* `swap-tokens (pool-id token-in token-out amount-in min-amount-out)`
  Swap tokens within a pool with fee deduction.

### Read-only Functions

* `get-amount-out (pool-id amount-in token-in)`
  Calculate output tokens for a given input amount.

* `get-pool (pool-id)`
  Retrieve pool details.

* `get-liquidity-position (pool-id provider)`
  Get liquidity position for a provider.

* `get-pool-by-tokens (token-a token-b)`
  Find pool by token pair.

* `get-pool-count`
  Get total number of pools created.

* `get-total-fees-collected`
  Get accumulated fees across all pools.

* `calculate-share-value (pool-id shares)`
  Calculate value of liquidity shares in terms of underlying tokens.

## Data Structures

* **liquidity-pools**: Tracks pool details including reserves and total shares.
* **liquidity-positions**: Records liquidity provider shares and activity.
* **token-pairs**: Maps token pairs to pool IDs.

## Error Codes

* `ERR-INSUFFICIENT-LIQUIDITY (u1200)` Not enough liquidity in pool
* `ERR-SLIPPAGE-EXCEEDED (u1201)` Slippage tolerance exceeded
* `ERR-INVALID-AMOUNT (u1202)` Invalid token amount
* `ERR-POOL-NOT-FOUND (u1203)` Pool does not exist
* `ERR-INSUFFICIENT-BALANCE (u1204)` Insufficient balance
* `ERR-ZERO-LIQUIDITY (u1205)` Pool has zero liquidity
* `ERR-MINIMUM-LIQUIDITY (u1206)` Minimum liquidity requirement not met
