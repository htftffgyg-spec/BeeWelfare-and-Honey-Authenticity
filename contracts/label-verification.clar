;; title: label-verification
;; version: 1.0.0
;; summary: QR verification connecting jars to origin and test results
;; description: Product traceability and consumer verification system with QR code integration

;; constants
(define-constant ERR-NOT-AUTHORIZED (err u500))
(define-constant ERR-INVALID-DATA (err u501))
(define-constant ERR-PRODUCT-NOT-FOUND (err u502))
(define-constant ERR-QR-CODE-EXISTS (err u503))
(define-constant ERR-BATCH-NOT-CERTIFIED (err u504))
(define-constant ERR-LABEL-EXPIRED (err u505))
(define-constant ERR-INVALID-QR-FORMAT (err u506))
(define-constant CONTRACT-OWNER tx-sender)

;; data vars
(define-data-var next-product-id uint u1)
(define-data-var next-label-id uint u1)
(define-data-var total-products uint u0)
(define-data-var total-verifications uint u0)

;; data maps
(define-map product-labels
  { product-id: uint }
  {
    batch-id: uint,
    producer: principal,
    product-name: (string-ascii 128),
    net-weight: uint,
    packaging-date: uint,
    expiry-date: uint,
    qr-code: (string-ascii 64),
    label-design-hash: (string-ascii 64),
    nutritional-info: (string-ascii 256),
    storage-instructions: (string-ascii 128),
    is-active: bool
  }
)

(define-map qr-code-registry
  { qr-code: (string-ascii 64) }
  {
    product-id: uint,
    batch-id: uint,
    apiary-id: uint,
    generation-date: uint,
    verification-count: uint,
    last-verified: uint,
    is-valid: bool,
    anti-counterfeiting-hash: (string-ascii 64)
  }
)

(define-map verification-logs
  { verification-id: uint }
  {
    qr-code: (string-ascii 64),
    verifier: (optional principal),
    verification-date: uint,
    location-data: (optional (string-ascii 128)),
    device-fingerprint: (string-ascii 64),
    verification-result: bool,
    authenticity-score: uint,
    warnings: (string-ascii 256)
  }
)

(define-map supply-chain-tracking
  { tracking-id: uint }
  {
    product-id: uint,
    stage: (string-ascii 32),
    location: (string-ascii 128),
    timestamp: uint,
    handler: principal,
    temperature: (optional int),
    humidity: (optional uint),
    notes: (string-ascii 256),
    verified: bool
  }
)

(define-map consumer-reports
  { report-id: uint }
  {
    product-id: uint,
    qr-code: (string-ascii 64),
    reporter: (optional principal),
    report-type: (string-ascii 32),
    description: (string-ascii 512),
    evidence-hash: (optional (string-ascii 64)),
    report-date: uint,
    status: (string-ascii 16),
    resolution: (optional (string-ascii 256))
  }
)

(define-map retailer-network
  { retailer-id: principal }
  {
    name: (string-ascii 128),
    location: (string-ascii 256),
    license-number: (string-ascii 32),
    verification-level: uint,
    products-handled: uint,
    last-audit: uint,
    is-authorized: bool
  }
)

;; private functions
(define-private (min (a uint) (b uint))
  (if (<= a b) a b)
)

(define-private (is-valid-qr-format (qr-code (string-ascii 64)))
  (and
    (>= (len qr-code) u12)
    (<= (len qr-code) u64)
  )
)

(define-private (generate-anti-counterfeiting-hash (qr-code (string-ascii 64)) (timestamp uint) (batch-id uint))
  ;; This would generate a cryptographic hash for anti-counterfeiting
  ;; Simplified implementation
  "hash_verified"
)

(define-private (calculate-authenticity-score (batch-certified bool) (qr-valid bool) (supply-chain-verified bool) (recent-verifications uint))
  (let
    (
      (base-score (if batch-certified u40 u10))
      (qr-score (if qr-valid u30 u0))
      (chain-score (if supply-chain-verified u20 u5))
      (verification-score (if (> recent-verifications u10) u10 (/ recent-verifications u1)))
    )
    (min (+ base-score qr-score chain-score verification-score) u100)
  )
)

(define-private (is-product-expired (expiry-date uint))
  (> stacks-block-height expiry-date)
)

(define-private (increment-verification-count (qr-code (string-ascii 64)))
  (match (map-get? qr-code-registry { qr-code: qr-code })
    qr-data
      (map-set qr-code-registry
        { qr-code: qr-code }
        (merge qr-data {
          verification-count: (+ (get verification-count qr-data) u1),
          last-verified: stacks-block-height
        })
      )
    false
  )
)

(define-private (validate-supply-chain-stage (current-stage (string-ascii 32)) (previous-stage (string-ascii 32)))
  ;; Define valid stage transitions
  (or
    (and (is-eq previous-stage "production") (is-eq current-stage "packaging"))
    (and (is-eq previous-stage "packaging") (is-eq current-stage "distribution"))
    (and (is-eq previous-stage "distribution") (is-eq current-stage "retail"))
    (and (is-eq previous-stage "retail") (is-eq current-stage "consumer"))
  )
)

;; public functions
(define-public (create-product-label
    (batch-id uint)
    (product-name (string-ascii 128))
    (net-weight uint)
    (expiry-date uint)
    (qr-code (string-ascii 64))
    (label-design-hash (string-ascii 64))
    (nutritional-info (string-ascii 256))
    (storage-instructions (string-ascii 128))
  )
  (let
    (
      (product-id (var-get next-product-id))
      (current-block stacks-block-height)
      (anti-counterfeiting (generate-anti-counterfeiting-hash qr-code current-block batch-id))
    )
    (asserts! (> (len product-name) u0) ERR-INVALID-DATA)
    (asserts! (> net-weight u0) ERR-INVALID-DATA)
    (asserts! (> expiry-date current-block) ERR-INVALID-DATA)
    (asserts! (is-valid-qr-format qr-code) ERR-INVALID-QR-FORMAT)
    (asserts! (is-none (map-get? qr-code-registry { qr-code: qr-code })) ERR-QR-CODE-EXISTS)
    
    ;; Create product label
    (map-set product-labels
      { product-id: product-id }
      {
        batch-id: batch-id,
        producer: tx-sender,
        product-name: product-name,
        net-weight: net-weight,
        packaging-date: current-block,
        expiry-date: expiry-date,
        qr-code: qr-code,
        label-design-hash: label-design-hash,
        nutritional-info: nutritional-info,
        storage-instructions: storage-instructions,
        is-active: true
      }
    )
    
    ;; Register QR code
    (map-set qr-code-registry
      { qr-code: qr-code }
      {
        product-id: product-id,
        batch-id: batch-id,
        apiary-id: u1, ;; This would come from batch data in real implementation
        generation-date: current-block,
        verification-count: u0,
        last-verified: u0,
        is-valid: true,
        anti-counterfeiting-hash: anti-counterfeiting
      }
    )
    
    (var-set next-product-id (+ product-id u1))
    (var-set total-products (+ (var-get total-products) u1))
    (ok product-id)
  )
)

(define-public (verify-product-qr
    (qr-code (string-ascii 64))
    (location-data (optional (string-ascii 128)))
    (device-fingerprint (string-ascii 64))
  )
  (let
    (
      (verification-id (+ (var-get total-verifications) u1))
      (current-block stacks-block-height)
      (qr-data (unwrap! (map-get? qr-code-registry { qr-code: qr-code }) ERR-PRODUCT-NOT-FOUND))
      (product-data (unwrap! (map-get? product-labels { product-id: (get product-id qr-data) }) ERR-PRODUCT-NOT-FOUND))
      (is-expired (is-product-expired (get expiry-date product-data)))
      (authenticity-score (calculate-authenticity-score true (get is-valid qr-data) true (get verification-count qr-data)))
    )
    (asserts! (get is-active product-data) ERR-PRODUCT-NOT-FOUND)
    (asserts! (get is-valid qr-data) ERR-INVALID-QR-FORMAT)
    
    ;; Log verification
    (map-set verification-logs
      { verification-id: verification-id }
      {
        qr-code: qr-code,
        verifier: (some tx-sender),
        verification-date: current-block,
        location-data: location-data,
        device-fingerprint: device-fingerprint,
        verification-result: (not is-expired),
        authenticity-score: authenticity-score,
        warnings: (if is-expired "Product expired" "")
      }
    )
    
    ;; Increment verification count
    (increment-verification-count qr-code)
    
    (var-set total-verifications verification-id)
    (ok {
      product-id: (get product-id qr-data),
      batch-id: (get batch-id qr-data),
      authentic: (not is-expired),
      authenticity-score: authenticity-score,
      product-name: (get product-name product-data),
      expiry-date: (get expiry-date product-data),
      warnings: (if is-expired (some "Product has expired") none)
    })
  )
)

(define-public (track-supply-chain-movement
    (product-id uint)
    (stage (string-ascii 32))
    (location (string-ascii 128))
    (handler principal)
    (temperature (optional int))
    (humidity (optional uint))
    (notes (string-ascii 256))
  )
  (let
    (
      (tracking-id (+ product-id (* stacks-block-height u100)))
      (current-block stacks-block-height)
    )
    (asserts! (is-some (map-get? product-labels { product-id: product-id })) ERR-PRODUCT-NOT-FOUND)
    (asserts! (> (len stage) u0) ERR-INVALID-DATA)
    (asserts! (> (len location) u0) ERR-INVALID-DATA)
    
    (map-set supply-chain-tracking
      { tracking-id: tracking-id }
      {
        product-id: product-id,
        stage: stage,
        location: location,
        timestamp: current-block,
        handler: handler,
        temperature: temperature,
        humidity: humidity,
        notes: notes,
        verified: false
      }
    )
    (ok tracking-id)
  )
)

(define-public (submit-consumer-report
    (product-id uint)
    (qr-code (string-ascii 64))
    (report-type (string-ascii 32))
    (description (string-ascii 512))
    (evidence-hash (optional (string-ascii 64)))
  )
  (let
    (
      (report-id (+ product-id (* stacks-block-height u10)))
      (current-block stacks-block-height)
    )
    (asserts! (is-some (map-get? product-labels { product-id: product-id })) ERR-PRODUCT-NOT-FOUND)
    (asserts! (is-some (map-get? qr-code-registry { qr-code: qr-code })) ERR-INVALID-QR-FORMAT)
    (asserts! (> (len description) u10) ERR-INVALID-DATA)
    
    (map-set consumer-reports
      { report-id: report-id }
      {
        product-id: product-id,
        qr-code: qr-code,
        reporter: (some tx-sender),
        report-type: report-type,
        description: description,
        evidence-hash: evidence-hash,
        report-date: current-block,
        status: "pending",
        resolution: none
      }
    )
    (ok report-id)
  )
)

(define-public (register-retailer
    (retailer-id principal)
    (name (string-ascii 128))
    (location (string-ascii 256))
    (license-number (string-ascii 32))
  )
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (> (len name) u0) ERR-INVALID-DATA)
    (asserts! (> (len license-number) u0) ERR-INVALID-DATA)
    
    (map-set retailer-network
      { retailer-id: retailer-id }
      {
        name: name,
        location: location,
        license-number: license-number,
        verification-level: u3,
        products-handled: u0,
        last-audit: stacks-block-height,
        is-authorized: true
      }
    )
    (ok true)
  )
)

(define-public (deactivate-product-label (product-id uint))
  (match (map-get? product-labels { product-id: product-id })
    product-data
      (begin
        (asserts! (or (is-eq tx-sender (get producer product-data)) (is-eq tx-sender CONTRACT-OWNER)) ERR-NOT-AUTHORIZED)
        (map-set product-labels
          { product-id: product-id }
          (merge product-data { is-active: false })
        )
        ;; Also deactivate associated QR code
        (match (map-get? qr-code-registry { qr-code: (get qr-code product-data) })
          qr-data
            (map-set qr-code-registry
              { qr-code: (get qr-code product-data) }
              (merge qr-data { is-valid: false })
            )
          false
        )
        (ok true)
      )
    ERR-PRODUCT-NOT-FOUND
  )
)

(define-public (resolve-consumer-report (report-id uint) (resolution (string-ascii 256)))
  (match (map-get? consumer-reports { report-id: report-id })
    report-data
      (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
        (map-set consumer-reports
          { report-id: report-id }
          (merge report-data {
            status: "resolved",
            resolution: (some resolution)
          })
        )
        (ok true)
      )
    ERR-PRODUCT-NOT-FOUND
  )
)

;; read only functions
(define-read-only (get-product-label (product-id uint))
  (map-get? product-labels { product-id: product-id })
)

(define-read-only (get-qr-code-info (qr-code (string-ascii 64)))
  (map-get? qr-code-registry { qr-code: qr-code })
)

(define-read-only (get-verification-log (verification-id uint))
  (map-get? verification-logs { verification-id: verification-id })
)

(define-read-only (get-supply-chain-tracking (tracking-id uint))
  (map-get? supply-chain-tracking { tracking-id: tracking-id })
)

(define-read-only (get-consumer-report (report-id uint))
  (map-get? consumer-reports { report-id: report-id })
)

(define-read-only (get-retailer-info (retailer-id principal))
  (map-get? retailer-network { retailer-id: retailer-id })
)

(define-read-only (get-contract-stats)
  {
    total-products: (var-get total-products),
    total-verifications: (var-get total-verifications),
    next-product-id: (var-get next-product-id),
    next-label-id: (var-get next-label-id)
  }
)

(define-read-only (verify-product-authenticity (qr-code (string-ascii 64)))
  (match (map-get? qr-code-registry { qr-code: qr-code })
    qr-data
      (match (map-get? product-labels { product-id: (get product-id qr-data) })
        product-data
          {
            authentic: (and (get is-valid qr-data) (get is-active product-data) (not (is-product-expired (get expiry-date product-data)))),
            product-name: (get product-name product-data),
            batch-id: (get batch-id qr-data),
            verification-count: (get verification-count qr-data),
            expiry-date: (get expiry-date product-data)
          }
        { authentic: false, product-name: "", batch-id: u0, verification-count: u0, expiry-date: u0 }
      )
    { authentic: false, product-name: "", batch-id: u0, verification-count: u0, expiry-date: u0 }
  )
)

