;; Automated Market Maker (AMM) Contract
;; A simple AMM for token swapping with liquidity pools

;; Error constants
(define-constant ERR-INSUFFICIENT-LIQUIDITY (err u1200))
(define-constant ERR-SLIPPAGE-EXCEEDED (err u1201))
(define-constant ERR-INVALID-AMOUNT (err u1202))
(define-constant ERR-POOL-NOT-FOUND (err u1203))
(define-constant ERR-INSUFFICIENT-BALANCE (err u1204))
(define-constant ERR-ZERO-LIQUIDITY (err u1205))
(define-constant ERR-MINIMUM-LIQUIDITY (err u1206))

;; Constants
(define-constant MINIMUM-LIQUIDITY u1000)
(define-constant FEE-RATE u30) ;; 0.3% fee

;; Data variables
(define-data-var pool-counter uint u0)
(define-data-var total-fee-collected uint u0)

;; SIP-010 token trait
(define-trait sip-010-trait
  (
    (transfer (uint principal principal (optional (buff 34))) (response bool uint))
    (get-name () (response (string-ascii 32) uint))
    (get-symbol () (response (string-ascii 32) uint))
    (get-decimals () (response uint uint))
    (get-balance (principal) (response uint uint))
    (get-total-supply () (response uint uint))
  )
)

;; Data maps
(define-map liquidity-pools
  { pool-id: uint }
  {
    token-a: principal,
    token-b: principal,
    reserve-a: uint,
    reserve-b: uint,
    total-shares: uint,
    created-at: uint
  }
)

(define-map liquidity-positions
  { pool-id: uint, provider: principal }
  { shares: uint, last-action: uint }
)

(define-map token-pairs
  { token-a: principal, token-b: principal }
  { pool-id: uint }
)

;; Create a new liquidity pool
(define-public (create-pool
  (token-a <sip-010-trait>)
  (token-b <sip-010-trait>)
  (amount-a uint)
  (amount-b uint)
)
  (let
    (
      (pool-id (+ (var-get pool-counter) u1))
      (token-a-principal (contract-of token-a))
      (token-b-principal (contract-of token-b))
      (initial-shares (pow (+ (* amount-a amount-b) u1) u1))
    )
    (asserts! (> amount-a u0) ERR-INVALID-AMOUNT)
    (asserts! (> amount-b u0) ERR-INVALID-AMOUNT)
    (asserts! (not (is-eq token-a-principal token-b-principal)) ERR-INVALID-AMOUNT)
    (asserts! (is-none (map-get? token-pairs { token-a: token-a-principal, token-b: token-b-principal })) ERR-POOL-NOT-FOUND)
    (asserts! (is-none (map-get? token-pairs { token-a: token-b-principal, token-b: token-a-principal })) ERR-POOL-NOT-FOUND)
    
    ;; Transfer tokens from user to contract
    (try! (contract-call? token-a transfer amount-a tx-sender (as-contract tx-sender) none))
    (try! (contract-call? token-b transfer amount-b tx-sender (as-contract tx-sender) none))
    
    ;; Create pool
    (map-set liquidity-pools
      { pool-id: pool-id }
      {
        token-a: token-a-principal,
        token-b: token-b-principal,
        reserve-a: amount-a,
        reserve-b: amount-b,
        total-shares: initial-shares,
        created-at: block-height
      }
    )
    
    ;; Set token pair mappings
    (map-set token-pairs
      { token-a: token-a-principal, token-b: token-b-principal }
      { pool-id: pool-id }
    )
    
    ;; Give initial liquidity shares to creator
    (map-set liquidity-positions
      { pool-id: pool-id, provider: tx-sender }
      { shares: initial-shares, last-action: block-height }
    )
    
    (var-set pool-counter pool-id)
    (ok pool-id)
  )
)

;; Add liquidity to existing pool
(define-public (add-liquidity
  (pool-id uint)
  (token-a <sip-010-trait>)
  (token-b <sip-010-trait>)
  (amount-a uint)
  (amount-b uint)
  (min-shares uint)
)
  (let
    (
      (pool-data (unwrap! (map-get? liquidity-pools { pool-id: pool-id }) ERR-POOL-NOT-FOUND))
      (reserve-a (get reserve-a pool-data))
      (reserve-b (get reserve-b pool-data))
      (total-shares (get total-shares pool-data))
      (optimal-amount-b (/ (* amount-a reserve-b) reserve-a))
      (optimal-amount-a (/ (* amount-b reserve-a) reserve-b))
      (actual-amount-a (if (<= optimal-amount-a amount-a) optimal-amount-a amount-a))
      (actual-amount-b (if (<= optimal-amount-b amount-b) optimal-amount-b amount-b))
      (shares-minted (/ (* actual-amount-a total-shares) reserve-a))
      (current-position (default-to { shares: u0, last-action: u0 } 
        (map-get? liquidity-positions { pool-id: pool-id, provider: tx-sender })))
    )
    (asserts! (>= shares-minted min-shares) ERR-SLIPPAGE-EXCEEDED)
    (asserts! (> shares-minted u0) ERR-INVALID-AMOUNT)
    
    ;; Transfer tokens
    (try! (contract-call? token-a transfer actual-amount-a tx-sender (as-contract tx-sender) none))
    (try! (contract-call? token-b transfer actual-amount-b tx-sender (as-contract tx-sender) none))
    
    ;; Update pool reserves and shares
    (map-set liquidity-pools
      { pool-id: pool-id }
      (merge pool-data {
        reserve-a: (+ reserve-a actual-amount-a),
        reserve-b: (+ reserve-b actual-amount-b),
        total-shares: (+ total-shares shares-minted)
      })
    )
    
    ;; Update user position
    (map-set liquidity-positions
      { pool-id: pool-id, provider: tx-sender }
      {
        shares: (+ (get shares current-position) shares-minted),
        last-action: block-height
      }
    )
    
    (ok { shares-minted: shares-minted, amount-a: actual-amount-a, amount-b: actual-amount-b })
  )
)

;; Remove liquidity from pool
(define-public (remove-liquidity
  (pool-id uint)
  (token-a <sip-010-trait>)
  (token-b <sip-010-trait>)
  (shares uint)
  (min-amount-a uint)
  (min-amount-b uint)
)
  (let
    (
      (pool-data (unwrap! (map-get? liquidity-pools { pool-id: pool-id }) ERR-POOL-NOT-FOUND))
      (user-position (unwrap! (map-get? liquidity-positions { pool-id: pool-id, provider: tx-sender }) ERR-INSUFFICIENT-LIQUIDITY))
      (reserve-a (get reserve-a pool-data))
      (reserve-b (get reserve-b pool-data))
      (total-shares (get total-shares pool-data))
      (amount-a (/ (* shares reserve-a) total-shares))
      (amount-b (/ (* shares reserve-b) total-shares))
    )
    (asserts! (>= (get shares user-position) shares) ERR-INSUFFICIENT-LIQUIDITY)
    (asserts! (>= amount-a min-amount-a) ERR-SLIPPAGE-EXCEEDED)
    (asserts! (>= amount-b min-amount-b) ERR-SLIPPAGE-EXCEEDED)
    (asserts! (> shares u0) ERR-INVALID-AMOUNT)
    
    ;; Transfer tokens back to user
    (try! (as-contract (contract-call? token-a transfer amount-a tx-sender tx-sender none)))
    (try! (as-contract (contract-call? token-b transfer amount-b tx-sender tx-sender none)))
    
    ;; Update pool reserves and shares
    (map-set liquidity-pools
      { pool-id: pool-id }
      (merge pool-data {
        reserve-a: (- reserve-a amount-a),
        reserve-b: (- reserve-b amount-b),
        total-shares: (- total-shares shares)
      })
    )
    
    ;; Update user position
    (let ((remaining-shares (- (get shares user-position) shares)))
      (if (> remaining-shares u0)
        (map-set liquidity-positions
          { pool-id: pool-id, provider: tx-sender }
          { shares: remaining-shares, last-action: block-height }
        )
        (map-delete liquidity-positions { pool-id: pool-id, provider: tx-sender })
      )
    )
    
    (ok { amount-a: amount-a, amount-b: amount-b })
  )
)

;; Swap tokens
(define-public (swap-tokens
  (pool-id uint)
  (token-in <sip-010-trait>)
  (token-out <sip-010-trait>)
  (amount-in uint)
  (min-amount-out uint)
)
  (let
    (
      (pool-data (unwrap! (map-get? liquidity-pools { pool-id: pool-id }) ERR-POOL-NOT-FOUND))
      (token-in-principal (contract-of token-in))
      (token-out-principal (contract-of token-out))
      (is-a-to-b (is-eq token-in-principal (get token-a pool-data)))
      (reserve-in (if is-a-to-b (get reserve-a pool-data) (get reserve-b pool-data)))
      (reserve-out (if is-a-to-b (get reserve-b pool-data) (get reserve-a pool-data)))
      (amount-in-with-fee (- amount-in (/ (* amount-in FEE-RATE) u10000)))
      (amount-out (/ (* amount-in-with-fee reserve-out) (+ reserve-in amount-in-with-fee)))
    )
    (asserts! (> amount-in u0) ERR-INVALID-AMOUNT)
    (asserts! (>= amount-out min-amount-out) ERR-SLIPPAGE-EXCEEDED)
    (asserts! (< amount-out reserve-out) ERR-INSUFFICIENT-LIQUIDITY)
    (asserts! 
      (or 
        (and (is-eq token-in-principal (get token-a pool-data)) (is-eq token-out-principal (get token-b pool-data)))
        (and (is-eq token-in-principal (get token-b pool-data)) (is-eq token-out-principal (get token-a pool-data)))
      ) 
      ERR-POOL-NOT-FOUND
    )
    
    ;; Transfer input token from user to contract
    (try! (contract-call? token-in transfer amount-in tx-sender (as-contract tx-sender) none))
    
    ;; Transfer output token from contract to user
    (try! (as-contract (contract-call? token-out transfer amount-out tx-sender tx-sender none)))
    
    ;; Update pool reserves
    (map-set liquidity-pools
      { pool-id: pool-id }
      (merge pool-data 
        (if is-a-to-b
          { reserve-a: (+ reserve-in amount-in), reserve-b: (- reserve-out amount-out) }
          { reserve-a: (- reserve-out amount-out), reserve-b: (+ reserve-in amount-in) }
        )
      )
    )
    
    ;; Update fee collection
    (var-set total-fee-collected (+ (var-get total-fee-collected) (- amount-in amount-in-with-fee)))
    
    (ok amount-out)
  )
)

;; Calculate swap output amount
(define-read-only (get-amount-out (pool-id uint) (amount-in uint) (token-in principal))
  (match (map-get? liquidity-pools { pool-id: pool-id })
    pool-data
      (let
        (
          (is-a-to-b (is-eq token-in (get token-a pool-data)))
          (reserve-in (if is-a-to-b (get reserve-a pool-data) (get reserve-b pool-data)))
          (reserve-out (if is-a-to-b (get reserve-b pool-data) (get reserve-a pool-data)))
          (amount-in-with-fee (- amount-in (/ (* amount-in FEE-RATE) u10000)))
        )
        (if (> amount-in u0)
          (some (/ (* amount-in-with-fee reserve-out) (+ reserve-in amount-in-with-fee)))
          none
        )
      )
    none
  )
)

;; Read-only functions
(define-read-only (get-pool (pool-id uint))
  (map-get? liquidity-pools { pool-id: pool-id })
)

(define-read-only (get-liquidity-position (pool-id uint) (provider principal))
  (map-get? liquidity-positions { pool-id: pool-id, provider: provider })
)

(define-read-only (get-pool-by-tokens (token-a principal) (token-b principal))
  (match (map-get? token-pairs { token-a: token-a, token-b: token-b })
    pair-data (map-get? liquidity-pools { pool-id: (get pool-id pair-data) })
    (match (map-get? token-pairs { token-a: token-b, token-b: token-a })
      pair-data (map-get? liquidity-pools { pool-id: (get pool-id pair-data) })
      none
    )
  )
)

(define-read-only (get-pool-count)
  (var-get pool-counter)
)

(define-read-only (get-total-fees-collected)
  (var-get total-fee-collected)
)

(define-read-only (calculate-share-value (pool-id uint) (shares uint))
  (match (map-get? liquidity-pools { pool-id: pool-id })
    pool-data
      (let
        (
          (total-shares (get total-shares pool-data))
        )
        (if (> total-shares u0)
          {
            amount-a: (/ (* shares (get reserve-a pool-data)) total-shares),
            amount-b: (/ (* shares (get reserve-b pool-data)) total-shares)
          }
          { amount-a: u0, amount-b: u0 }
        )
      )
    { amount-a: u0, amount-b: u0 }
  )
)