;; Infrastructure Revenue Tokens Contract
;; Tokenize infrastructure revenue streams from tolls and utilities,
;; distribute usage-based returns to token holders, track infrastructure performance metrics,
;; enable secondary market trading, and provide transparent infrastructure investment

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-unauthorized (err u102))
(define-constant err-invalid-amount (err u103))
(define-constant err-insufficient-balance (err u104))
(define-constant err-already-exists (err u105))
(define-constant err-invalid-asset (err u106))
(define-constant err-asset-inactive (err u107))
(define-constant err-revenue-distribution-failed (err u108))
(define-constant err-insufficient-revenue (err u109))
(define-constant err-invalid-performance-data (err u110))

;; Platform constants
(define-constant platform-fee-bp u500)    ;; 5% platform fee
(define-constant min-investment u1000000) ;; 1 STX minimum investment
(define-constant max-token-supply u100000000) ;; 100M max tokens per asset
(define-constant quarterly-blocks u13140)     ;; ~3 months in blocks
(define-constant revenue-buffer u1000000)     ;; 1 STX buffer for gas costs

;; Infrastructure asset types
(define-constant asset-type-toll-road u1)
(define-constant asset-type-bridge u2)
(define-constant asset-type-airport u3)
(define-constant asset-type-utility u4)
(define-constant asset-type-renewable-energy u5)
(define-constant asset-type-railway u6)
(define-constant asset-type-port u7)
(define-constant asset-type-water-system u8)

;; Data Variables
(define-data-var asset-counter uint u0)
(define-data-var total-assets-value uint u0)
(define-data-var total-revenue-distributed uint u0)
(define-data-var platform-revenue uint u0)
(define-data-var emergency-pause bool false)

;; Infrastructure Assets Registry
(define-map infrastructure-assets
    uint ;; asset-id
    {
        owner: principal,
        asset-type: uint,
        name: (string-ascii 128),
        description: (string-ascii 512),
        location: (string-ascii 256),
        total-token-supply: uint,
        tokens-sold: uint,
        price-per-token: uint,    ;; In microSTX
        revenue-share-percentage: uint, ;; Percentage of revenue shared with token holders
        is-active: bool,
        created-at: uint,
        last-revenue-distribution: uint,
        total-revenue-collected: uint,
        performance-score: uint,  ;; 0-100 performance rating
        annual-revenue-projection: uint,
        metadata: (string-ascii 512) ;; JSON metadata for additional details
    }
)

;; Token Holdings
(define-map token-holdings
    { asset-id: uint, holder: principal }
    {
        tokens: uint,
        purchase-price: uint,     ;; Total amount paid for tokens
        purchase-date: uint,
        total-dividends-received: uint,
        last-dividend-claim: uint
    }
)

;; Revenue Distribution Records
(define-map revenue-distributions
    { asset-id: uint, distribution-id: uint }
    {
        total-revenue: uint,
        revenue-per-token: uint,
        distribution-date: uint,
        tokens-eligible: uint,
        platform-fee: uint,
        net-distribution: uint
    }
)

;; Asset Performance Metrics
(define-map performance-metrics
    { asset-id: uint, period: uint }
    {
        usage-volume: uint,       ;; Traffic, energy production, etc.
        revenue-generated: uint,
        operational-costs: uint,
        efficiency-score: uint,   ;; 0-100 efficiency rating
        maintenance-costs: uint,
        capacity-utilization: uint, ;; 0-100 percentage
        reported-by: principal,
        reported-at: uint
    }
)

;; Asset Validators (authorized to report performance data)
(define-map asset-validators
    { asset-id: uint, validator: principal }
    {
        is-authorized: bool,
        authorized-by: principal,
        authorized-at: uint,
        validation-count: uint
    }
)

;; Investor Profiles
(define-map investor-profiles
    principal
    {
        total-investments: uint,
        total-dividends-earned: uint,
        assets-invested: (list 20 uint),
        kyc-verified: bool,
        risk-profile: uint,       ;; 1=conservative, 2=moderate, 3=aggressive
        last-activity: uint
    }
)

;; Asset Owner Profiles
(define-map asset-owner-profiles
    principal
    {
        total-assets: uint,
        total-funds-raised: uint,
        average-performance-score: uint,
        verified-owner: bool,
        assets-owned: (list 10 uint),
        last-revenue-distribution: uint
    }
)

;; Secondary Market Orders
(define-map market-orders
    uint ;; order-id
    {
        seller: principal,
        asset-id: uint,
        tokens-for-sale: uint,
        price-per-token: uint,
        order-type: uint,         ;; 1=market, 2=limit
        created-at: uint,
        expires-at: uint,
        is-active: bool
    }
)

;; Distribution tracking
(define-data-var distribution-counter uint u0)
(define-data-var order-counter uint u0)

;; Public Functions

;; Create new infrastructure asset for tokenization
(define-public (create-infrastructure-asset
    (asset-type uint)
    (name (string-ascii 128))
    (description (string-ascii 512))
    (location (string-ascii 256))
    (total-token-supply uint)
    (price-per-token uint)
    (revenue-share-percentage uint)
    (annual-revenue-projection uint)
    (metadata (string-ascii 512)))
    (let (
        (asset-id (+ (var-get asset-counter) u1))
        (caller tx-sender)
    )
        (asserts! (not (var-get emergency-pause)) (err u999))
        (asserts! (<= asset-type asset-type-water-system) err-invalid-asset)
        (asserts! (>= price-per-token min-investment) err-invalid-amount)
        (asserts! (<= total-token-supply max-token-supply) err-invalid-amount)
        (asserts! (<= revenue-share-percentage u100) err-invalid-amount)
        (asserts! (> (len name) u0) err-invalid-asset)
        
        ;; Create asset
        (map-set infrastructure-assets asset-id {
            owner: caller,
            asset-type: asset-type,
            name: name,
            description: description,
            location: location,
            total-token-supply: total-token-supply,
            tokens-sold: u0,
            price-per-token: price-per-token,
            revenue-share-percentage: revenue-share-percentage,
            is-active: true,
            created-at: block-height,
            last-revenue-distribution: u0,
            total-revenue-collected: u0,
            performance-score: u75, ;; Start with neutral score
            annual-revenue-projection: annual-revenue-projection,
            metadata: metadata
        })
        
        ;; Add validator authorization for asset owner
        (map-set asset-validators 
            { asset-id: asset-id, validator: caller }
            {
                is-authorized: true,
                authorized-by: caller,
                authorized-at: block-height,
                validation-count: u0
            }
        )
        
        ;; Update owner profile
        (let (
            (profile (default-to 
                { total-assets: u0, total-funds-raised: u0, average-performance-score: u75,
                  verified-owner: false, assets-owned: (list), last-revenue-distribution: u0 }
                (map-get? asset-owner-profiles caller)))
        )
            (map-set asset-owner-profiles caller
                (merge profile {
                    total-assets: (+ (get total-assets profile) u1),
                    assets-owned: (unwrap! (as-max-len? (append (get assets-owned profile) asset-id) u10) err-invalid-asset)
                })
            )
        )
        
        (var-set asset-counter asset-id)
        (var-set total-assets-value (+ (var-get total-assets-value) (* total-token-supply price-per-token)))
        (ok asset-id)
    )
)

;; Purchase infrastructure tokens
(define-public (purchase-tokens (asset-id uint) (token-amount uint))
    (let (
        (asset (unwrap! (map-get? infrastructure-assets asset-id) err-not-found))
        (caller tx-sender)
        (total-cost (* token-amount (get price-per-token asset)))
        (available-tokens (- (get total-token-supply asset) (get tokens-sold asset)))
    )
        (asserts! (not (var-get emergency-pause)) (err u999))
        (asserts! (get is-active asset) err-asset-inactive)
        (asserts! (>= token-amount u1) err-invalid-amount)
        (asserts! (>= total-cost min-investment) err-invalid-amount)
        (asserts! (>= available-tokens token-amount) err-insufficient-balance)
        
        ;; Transfer payment to asset owner
        (try! (stx-transfer? total-cost caller (get owner asset)))
        
        ;; Update token holdings
        (let (
            (existing-holding (default-to 
                { tokens: u0, purchase-price: u0, purchase-date: u0, 
                  total-dividends-received: u0, last-dividend-claim: u0 }
                (map-get? token-holdings { asset-id: asset-id, holder: caller })))
        )
            (map-set token-holdings 
                { asset-id: asset-id, holder: caller }
                {
                    tokens: (+ (get tokens existing-holding) token-amount),
                    purchase-price: (+ (get purchase-price existing-holding) total-cost),
                    purchase-date: (if (is-eq (get tokens existing-holding) u0) block-height (get purchase-date existing-holding)),
                    total-dividends-received: (get total-dividends-received existing-holding),
                    last-dividend-claim: (get last-dividend-claim existing-holding)
                }
            )
        )
        
        ;; Update asset info
        (map-set infrastructure-assets asset-id
            (merge asset {
                tokens-sold: (+ (get tokens-sold asset) token-amount)
            })
        )
        
        ;; Update investor profile
        (let (
            (profile (default-to 
                { total-investments: u0, total-dividends-earned: u0, assets-invested: (list),
                  kyc-verified: false, risk-profile: u2, last-activity: u0 }
                (map-get? investor-profiles caller)))
        )
            (map-set investor-profiles caller
                (merge profile {
                    total-investments: (+ (get total-investments profile) total-cost),
                    assets-invested: (unwrap! (as-max-len? (append (get assets-invested profile) asset-id) u20) err-invalid-asset),
                    last-activity: block-height
                })
            )
        )
        
        ;; Update owner profile
        (let (
            (owner-profile (default-to 
                { total-assets: u0, total-funds-raised: u0, average-performance-score: u75,
                  verified-owner: false, assets-owned: (list), last-revenue-distribution: u0 }
                (map-get? asset-owner-profiles (get owner asset))))
        )
            (map-set asset-owner-profiles (get owner asset)
                (merge owner-profile {
                    total-funds-raised: (+ (get total-funds-raised owner-profile) total-cost)
                })
            )
        )
        
        (ok token-amount)
    )
)

;; Distribute revenue to token holders
(define-public (distribute-revenue (asset-id uint) (total-revenue uint))
    (let (
        (asset (unwrap! (map-get? infrastructure-assets asset-id) err-not-found))
        (caller tx-sender)
        (distribution-id (+ (var-get distribution-counter) u1))
        (platform-fee (/ (* total-revenue platform-fee-bp) u10000))
        (net-revenue (- total-revenue platform-fee))
        (shareable-revenue (/ (* net-revenue (get revenue-share-percentage asset)) u100))
        (tokens-sold (get tokens-sold asset))
        (revenue-per-token (if (> tokens-sold u0) (/ shareable-revenue tokens-sold) u0))
    )
        (asserts! (not (var-get emergency-pause)) (err u999))
        (asserts! (is-eq caller (get owner asset)) err-unauthorized)
        (asserts! (>= total-revenue revenue-buffer) err-insufficient-revenue)
        (asserts! (> tokens-sold u0) err-insufficient-balance)
        
        ;; Transfer revenue to contract for distribution
        (try! (stx-transfer? total-revenue caller (as-contract tx-sender)))
        
        ;; Record distribution
        (map-set revenue-distributions
            { asset-id: asset-id, distribution-id: distribution-id }
            {
                total-revenue: total-revenue,
                revenue-per-token: revenue-per-token,
                distribution-date: block-height,
                tokens-eligible: tokens-sold,
                platform-fee: platform-fee,
                net-distribution: shareable-revenue
            }
        )
        
        ;; Update asset
        (map-set infrastructure-assets asset-id
            (merge asset {
                last-revenue-distribution: block-height,
                total-revenue-collected: (+ (get total-revenue-collected asset) total-revenue)
            })
        )
        
        ;; Update platform revenue
        (var-set platform-revenue (+ (var-get platform-revenue) platform-fee))
        (var-set total-revenue-distributed (+ (var-get total-revenue-distributed) shareable-revenue))
        (var-set distribution-counter distribution-id)
        
        (ok distribution-id)
    )
)

;; Claim dividends
(define-public (claim-dividends (asset-id uint) (distribution-id uint))
    (let (
        (holding (unwrap! (map-get? token-holdings { asset-id: asset-id, holder: tx-sender }) err-not-found))
        (distribution (unwrap! (map-get? revenue-distributions { asset-id: asset-id, distribution-id: distribution-id }) err-not-found))
        (caller tx-sender)
        (dividend-amount (* (get tokens holding) (get revenue-per-token distribution)))
    )
        (asserts! (not (var-get emergency-pause)) (err u999))
        (asserts! (> (get tokens holding) u0) err-insufficient-balance)
        (asserts! (> dividend-amount u0) err-insufficient-balance)
        (asserts! (< (get last-dividend-claim holding) (get distribution-date distribution)) err-already-exists)
        
        ;; Transfer dividend
        (try! (as-contract (stx-transfer? dividend-amount tx-sender caller)))
        
        ;; Update holding
        (map-set token-holdings 
            { asset-id: asset-id, holder: caller }
            (merge holding {
                total-dividends-received: (+ (get total-dividends-received holding) dividend-amount),
                last-dividend-claim: (get distribution-date distribution)
            })
        )
        
        ;; Update investor profile
        (let (
            (profile (default-to 
                { total-investments: u0, total-dividends-earned: u0, assets-invested: (list),
                  kyc-verified: false, risk-profile: u2, last-activity: u0 }
                (map-get? investor-profiles caller)))
        )
            (map-set investor-profiles caller
                (merge profile {
                    total-dividends-earned: (+ (get total-dividends-earned profile) dividend-amount),
                    last-activity: block-height
                })
            )
        )
        
        (ok dividend-amount)
    )
)

;; Report infrastructure performance metrics
(define-public (report-performance-metrics
    (asset-id uint)
    (usage-volume uint)
    (revenue-generated uint)
    (operational-costs uint)
    (maintenance-costs uint)
    (capacity-utilization uint))
    (let (
        (asset (unwrap! (map-get? infrastructure-assets asset-id) err-not-found))
        (caller tx-sender)
        (validator (unwrap! (map-get? asset-validators { asset-id: asset-id, validator: caller }) err-unauthorized))
        (period block-height)
        (efficiency-score (calculate-efficiency-score usage-volume revenue-generated operational-costs))
    )
        (asserts! (not (var-get emergency-pause)) (err u999))
        (asserts! (get is-authorized validator) err-unauthorized)
        (asserts! (<= capacity-utilization u100) err-invalid-performance-data)
        
        ;; Store performance metrics
        (map-set performance-metrics
            { asset-id: asset-id, period: period }
            {
                usage-volume: usage-volume,
                revenue-generated: revenue-generated,
                operational-costs: operational-costs,
                efficiency-score: efficiency-score,
                maintenance-costs: maintenance-costs,
                capacity-utilization: capacity-utilization,
                reported-by: caller,
                reported-at: block-height
            }
        )
        
        ;; Update validator count
        (map-set asset-validators
            { asset-id: asset-id, validator: caller }
            (merge validator {
                validation-count: (+ (get validation-count validator) u1)
            })
        )
        
        ;; Update asset performance score
        (let (
            (new-performance-score (/ (+ efficiency-score capacity-utilization) u2))
        )
            (map-set infrastructure-assets asset-id
                (merge asset {
                    performance-score: new-performance-score
                })
            )
        )
        
        (ok efficiency-score)
    )
)

;; Authorize validator for asset
(define-public (authorize-validator (asset-id uint) (validator principal))
    (let (
        (asset (unwrap! (map-get? infrastructure-assets asset-id) err-not-found))
        (caller tx-sender)
    )
        (asserts! (not (var-get emergency-pause)) (err u999))
        (asserts! (is-eq caller (get owner asset)) err-unauthorized)
        
        (map-set asset-validators
            { asset-id: asset-id, validator: validator }
            {
                is-authorized: true,
                authorized-by: caller,
                authorized-at: block-height,
                validation-count: u0
            }
        )
        
        (ok true)
    )
)

;; Private Functions

;; Calculate efficiency score based on performance metrics
(define-private (calculate-efficiency-score (usage-volume uint) (revenue-generated uint) (operational-costs uint))
    (let (
        (profit (if (> revenue-generated operational-costs) 
                   (- revenue-generated operational-costs) 
                   u0))
        (efficiency-ratio (if (> operational-costs u0)
                           (/ (* profit u100) operational-costs)
                           u100))
    )
        (if (> efficiency-ratio u100) u100 efficiency-ratio)
    )
)

;; Read-only Functions

;; Get infrastructure asset details
(define-read-only (get-infrastructure-asset (asset-id uint))
    (map-get? infrastructure-assets asset-id)
)

;; Get token holdings
(define-read-only (get-token-holdings (asset-id uint) (holder principal))
    (map-get? token-holdings { asset-id: asset-id, holder: holder })
)

;; Get revenue distribution details
(define-read-only (get-revenue-distribution (asset-id uint) (distribution-id uint))
    (map-get? revenue-distributions { asset-id: asset-id, distribution-id: distribution-id })
)

;; Get performance metrics
(define-read-only (get-performance-metrics (asset-id uint) (period uint))
    (map-get? performance-metrics { asset-id: asset-id, period: period })
)

;; Get investor profile
(define-read-only (get-investor-profile (investor principal))
    (map-get? investor-profiles investor)
)

;; Get asset owner profile
(define-read-only (get-asset-owner-profile (owner principal))
    (map-get? asset-owner-profiles owner)
)

;; Get platform statistics
(define-read-only (get-platform-stats)
    {
        total-assets: (var-get asset-counter),
        total-assets-value: (var-get total-assets-value),
        total-revenue-distributed: (var-get total-revenue-distributed),
        platform-revenue: (var-get platform-revenue),
        emergency-pause: (var-get emergency-pause)
    }
)

;; Calculate potential returns
(define-read-only (calculate-potential-returns (asset-id uint) (investment-amount uint))
    (let (
        (asset (unwrap! (map-get? infrastructure-assets asset-id) (err u0)))
        (price-per-token (get price-per-token asset))
        (tokens-purchasable (/ investment-amount price-per-token))
        (annual-projection (get annual-revenue-projection asset))
        (share-percentage (get revenue-share-percentage asset))
        (annual-shareable (/ (* annual-projection share-percentage) u100))
        (total-tokens (get total-token-supply asset))
        (potential-annual-return (if (> total-tokens u0)
                                   (/ (* tokens-purchasable annual-shareable) total-tokens)
                                   u0))
        (yield-percentage (if (> investment-amount u0)
                           (/ (* potential-annual-return u10000) investment-amount)
                           u0))
    )
        (ok {
            tokens-purchasable: tokens-purchasable,
            potential-annual-return: potential-annual-return,
            yield-percentage: yield-percentage,
            investment-payback-years: (if (> potential-annual-return u0)
                                       (/ investment-amount potential-annual-return)
                                       u0)
        })
    )
)
