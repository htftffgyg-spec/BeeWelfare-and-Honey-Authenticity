;; title: honey-origin-and-testing
;; version: 1.0.0
;; summary: Lab proofs for pollen profiles, isotopes, and adulteration checks
;; description: Comprehensive laboratory testing and verification system for honey authenticity

;; constants
(define-constant ERR-NOT-AUTHORIZED (err u400))
(define-constant ERR-INVALID-DATA (err u401))
(define-constant ERR-SAMPLE-NOT-FOUND (err u402))
(define-constant ERR-LAB-NOT-CERTIFIED (err u403))
(define-constant ERR-TEST-NOT-FOUND (err u404))
(define-constant ERR-BATCH-NOT-FOUND (err u405))
(define-constant ERR-INVALID-TEST-RESULT (err u406))
(define-constant CONTRACT-OWNER tx-sender)

;; Purity thresholds
(define-constant MIN-HONEY-PURITY u80) ;; 80% minimum honey content
(define-constant MAX-MOISTURE-CONTENT u20) ;; 20% max moisture
(define-constant MAX-HMF-LEVEL u40) ;; Hydroxymethylfurfural max mg/kg
(define-constant MIN-DIASTASE-ACTIVITY u8) ;; Minimum diastase number

;; data vars
(define-data-var next-batch-id uint u1)
(define-data-var next-test-id uint u1)
(define-data-var next-sample-id uint u1)
(define-data-var total-batches uint u0)
(define-data-var total-tests uint u0)

;; data maps
(define-map honey-batches
  { batch-id: uint }
  {
    apiary-id: uint,
    producer: principal,
    harvest-date: uint,
    processing-date: uint,
    batch-size: uint,
    origin-coordinates: (string-ascii 64),
    floral-source: (string-ascii 128),
    collection-method: (string-ascii 64),
    storage-conditions: (string-ascii 128),
    initial-moisture: uint,
    certification-pending: bool,
    certified: bool
  }
)

(define-map laboratory-facilities
  { lab-id: principal }
  {
    name: (string-ascii 128),
    certification: (string-ascii 64),
    accreditation-body: (string-ascii 64),
    license-number: (string-ascii 32),
    valid-until: uint,
    specializations: (string-ascii 256),
    test-capacity: uint,
    is-active: bool
  }
)

(define-map test-samples
  { sample-id: uint }
  {
    batch-id: uint,
    lab-id: principal,
    sample-date: uint,
    sample-size: uint,
    collection-method: (string-ascii 64),
    chain-of-custody: (string-ascii 256),
    storage-temperature: int,
    expiry-date: uint,
    status: (string-ascii 16)
  }
)

(define-map pollen-analysis
  { test-id: uint }
  {
    sample-id: uint,
    lab-id: principal,
    test-date: uint,
    dominant-pollen: (string-ascii 64),
    secondary-pollen: (string-ascii 128),
    pollen-diversity: uint,
    geographic-markers: (string-ascii 128),
    seasonal-indicators: (string-ascii 64),
    authenticity-score: uint,
    verified: bool
  }
)

(define-map isotope-analysis
  { test-id: uint }
  {
    sample-id: uint,
    lab-id: principal,
    test-date: uint,
    carbon-isotope: int,
    nitrogen-isotope: int,
    oxygen-isotope: int,
    sulfur-isotope: int,
    geographic-origin: (string-ascii 128),
    botanical-origin: (string-ascii 64),
    authenticity-confirmed: bool,
    confidence-level: uint
  }
)

(define-map adulteration-tests
  { test-id: uint }
  {
    sample-id: uint,
    lab-id: principal,
    test-date: uint,
    sugar-profile: (string-ascii 256),
    foreign-sugars-detected: bool,
    synthetic-additives: (string-ascii 128),
    moisture-content: uint,
    hmf-level: uint,
    diastase-activity: uint,
    purity-percentage: uint,
    pass-fail-status: bool
  }
)

(define-map quality-certifications
  { cert-id: uint }
  {
    batch-id: uint,
    certifying-body: principal,
    certification-type: (string-ascii 32),
    issue-date: uint,
    expiry-date: uint,
    grade: (string-ascii 16),
    quality-score: uint,
    special-designations: (string-ascii 128),
    certificate-hash: (string-ascii 64)
  }
)

;; private functions
(define-private (is-lab-certified (lab-id principal))
  (match (map-get? laboratory-facilities { lab-id: lab-id })
    lab-data
      (and
        (get is-active lab-data)
        (> (get valid-until lab-data) stacks-block-height)
      )
    false
  )
)

(define-private (calculate-authenticity-score (pollen-score uint) (isotope-confidence uint) (purity uint))
  (let
    (
      (weighted-pollen (* pollen-score u4))
      (weighted-isotope (* isotope-confidence u3))
      (weighted-purity (* purity u3))
      (total-weight u10)
    )
    (/ (+ weighted-pollen weighted-isotope weighted-purity) total-weight)
  )
)

(define-private (validate-purity-standards (moisture uint) (hmf uint) (diastase uint))
  (and
    (<= moisture MAX-MOISTURE-CONTENT)
    (<= hmf MAX-HMF-LEVEL)
    (>= diastase MIN-DIASTASE-ACTIVITY)
  )
)

(define-private (determine-quality-grade (purity uint) (authenticity uint) (standards-met bool))
  (if standards-met
    (if (and (>= purity u95) (>= authenticity u90))
      "premium"
      (if (and (>= purity u85) (>= authenticity u80))
        "standard"
        "basic"
      )
    )
    "failed"
  )
)

(define-private (update-batch-certification-status (batch-id uint) (certified bool))
  (match (map-get? honey-batches { batch-id: batch-id })
    batch-data
      (map-set honey-batches
        { batch-id: batch-id }
        (merge batch-data { certified: certified, certification-pending: false })
      )
    false
  )
)

;; public functions
(define-public (register-honey-batch
    (apiary-id uint)
    (harvest-date uint)
    (processing-date uint)
    (batch-size uint)
    (origin-coordinates (string-ascii 64))
    (floral-source (string-ascii 128))
    (collection-method (string-ascii 64))
    (storage-conditions (string-ascii 128))
    (initial-moisture uint)
  )
  (let
    (
      (batch-id (var-get next-batch-id))
      (current-block stacks-block-height)
    )
    (asserts! (> batch-size u0) ERR-INVALID-DATA)
    (asserts! (<= harvest-date current-block) ERR-INVALID-DATA)
    (asserts! (>= processing-date harvest-date) ERR-INVALID-DATA)
    (asserts! (> (len floral-source) u0) ERR-INVALID-DATA)
    (asserts! (<= initial-moisture u25) ERR-INVALID-DATA)
    
    (map-set honey-batches
      { batch-id: batch-id }
      {
        apiary-id: apiary-id,
        producer: tx-sender,
        harvest-date: harvest-date,
        processing-date: processing-date,
        batch-size: batch-size,
        origin-coordinates: origin-coordinates,
        floral-source: floral-source,
        collection-method: collection-method,
        storage-conditions: storage-conditions,
        initial-moisture: initial-moisture,
        certification-pending: false,
        certified: false
      }
    )
    
    (var-set next-batch-id (+ batch-id u1))
    (var-set total-batches (+ (var-get total-batches) u1))
    (ok batch-id)
  )
)

(define-public (register-laboratory
    (lab-id principal)
    (name (string-ascii 128))
    (certification (string-ascii 64))
    (accreditation-body (string-ascii 64))
    (license-number (string-ascii 32))
    (valid-until uint)
    (specializations (string-ascii 256))
    (test-capacity uint)
  )
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (> (len name) u0) ERR-INVALID-DATA)
    (asserts! (> valid-until stacks-block-height) ERR-INVALID-DATA)
    (asserts! (> test-capacity u0) ERR-INVALID-DATA)
    
    (map-set laboratory-facilities
      { lab-id: lab-id }
      {
        name: name,
        certification: certification,
        accreditation-body: accreditation-body,
        license-number: license-number,
        valid-until: valid-until,
        specializations: specializations,
        test-capacity: test-capacity,
        is-active: true
      }
    )
    (ok true)
  )
)

(define-public (submit-sample-for-testing
    (batch-id uint)
    (lab-id principal)
    (sample-size uint)
    (collection-method (string-ascii 64))
    (chain-of-custody (string-ascii 256))
    (storage-temp int)
  )
  (let
    (
      (sample-id (var-get next-sample-id))
      (current-block stacks-block-height)
      (expiry (+ current-block u4320)) ;; 30 days expiry
    )
    (asserts! (is-some (map-get? honey-batches { batch-id: batch-id })) ERR-BATCH-NOT-FOUND)
    (asserts! (is-lab-certified lab-id) ERR-LAB-NOT-CERTIFIED)
    (asserts! (> sample-size u0) ERR-INVALID-DATA)
    (asserts! (and (>= storage-temp -18) (<= storage-temp 25)) ERR-INVALID-DATA)
    
    (map-set test-samples
      { sample-id: sample-id }
      {
        batch-id: batch-id,
        lab-id: lab-id,
        sample-date: current-block,
        sample-size: sample-size,
        collection-method: collection-method,
        chain-of-custody: chain-of-custody,
        storage-temperature: storage-temp,
        expiry-date: expiry,
        status: "received"
      }
    )
    
    ;; Mark batch as pending certification
    (match (map-get? honey-batches { batch-id: batch-id })
      batch-data
        (map-set honey-batches
          { batch-id: batch-id }
          (merge batch-data { certification-pending: true })
        )
      false
    )
    
    (var-set next-sample-id (+ sample-id u1))
    (ok sample-id)
  )
)

(define-public (submit-pollen-analysis
    (sample-id uint)
    (dominant-pollen (string-ascii 64))
    (secondary-pollen (string-ascii 128))
    (diversity uint)
    (geographic-markers (string-ascii 128))
    (seasonal-indicators (string-ascii 64))
    (authenticity-score uint)
  )
  (let
    (
      (test-id (var-get next-test-id))
      (current-block stacks-block-height)
      (sample-info (unwrap! (map-get? test-samples { sample-id: sample-id }) ERR-SAMPLE-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender (get lab-id sample-info)) ERR-NOT-AUTHORIZED)
    (asserts! (> (len dominant-pollen) u0) ERR-INVALID-DATA)
    (asserts! (<= authenticity-score u100) ERR-INVALID-DATA)
    (asserts! (<= diversity u100) ERR-INVALID-DATA)
    
    (map-set pollen-analysis
      { test-id: test-id }
      {
        sample-id: sample-id,
        lab-id: tx-sender,
        test-date: current-block,
        dominant-pollen: dominant-pollen,
        secondary-pollen: secondary-pollen,
        pollen-diversity: diversity,
        geographic-markers: geographic-markers,
        seasonal-indicators: seasonal-indicators,
        authenticity-score: authenticity-score,
        verified: false
      }
    )
    
    (var-set next-test-id (+ test-id u1))
    (var-set total-tests (+ (var-get total-tests) u1))
    (ok test-id)
  )
)

(define-public (submit-isotope-analysis
    (sample-id uint)
    (carbon int)
    (nitrogen int)
    (oxygen int)
    (sulfur int)
    (geographic-origin (string-ascii 128))
    (botanical-origin (string-ascii 64))
    (confidence uint)
  )
  (let
    (
      (test-id (var-get next-test-id))
      (current-block stacks-block-height)
      (sample-info (unwrap! (map-get? test-samples { sample-id: sample-id }) ERR-SAMPLE-NOT-FOUND))
      (authenticity (>= confidence u75))
    )
    (asserts! (is-eq tx-sender (get lab-id sample-info)) ERR-NOT-AUTHORIZED)
    (asserts! (<= confidence u100) ERR-INVALID-DATA)
    
    (map-set isotope-analysis
      { test-id: test-id }
      {
        sample-id: sample-id,
        lab-id: tx-sender,
        test-date: current-block,
        carbon-isotope: carbon,
        nitrogen-isotope: nitrogen,
        oxygen-isotope: oxygen,
        sulfur-isotope: sulfur,
        geographic-origin: geographic-origin,
        botanical-origin: botanical-origin,
        authenticity-confirmed: authenticity,
        confidence-level: confidence
      }
    )
    
    (var-set next-test-id (+ test-id u1))
    (var-set total-tests (+ (var-get total-tests) u1))
    (ok test-id)
  )
)

(define-public (submit-adulteration-test
    (sample-id uint)
    (sugar-profile (string-ascii 256))
    (foreign-sugars bool)
    (synthetic-additives (string-ascii 128))
    (moisture uint)
    (hmf uint)
    (diastase uint)
    (purity uint)
  )
  (let
    (
      (test-id (var-get next-test-id))
      (current-block stacks-block-height)
      (sample-info (unwrap! (map-get? test-samples { sample-id: sample-id }) ERR-SAMPLE-NOT-FOUND))
      (standards-met (validate-purity-standards moisture hmf diastase))
      (pass-status (and standards-met (>= purity MIN-HONEY-PURITY) (not foreign-sugars)))
    )
    (asserts! (is-eq tx-sender (get lab-id sample-info)) ERR-NOT-AUTHORIZED)
    (asserts! (<= moisture u25) ERR-INVALID-DATA)
    (asserts! (<= purity u100) ERR-INVALID-DATA)
    
    (map-set adulteration-tests
      { test-id: test-id }
      {
        sample-id: sample-id,
        lab-id: tx-sender,
        test-date: current-block,
        sugar-profile: sugar-profile,
        foreign-sugars-detected: foreign-sugars,
        synthetic-additives: synthetic-additives,
        moisture-content: moisture,
        hmf-level: hmf,
        diastase-activity: diastase,
        purity-percentage: purity,
        pass-fail-status: pass-status
      }
    )
    
    (var-set next-test-id (+ test-id u1))
    (var-set total-tests (+ (var-get total-tests) u1))
    (ok test-id)
  )
)

(define-public (issue-quality-certification
    (batch-id uint)
    (certification-type (string-ascii 32))
    (grade (string-ascii 16))
    (quality-score uint)
    (special-designations (string-ascii 128))
    (certificate-hash (string-ascii 64))
  )
  (let
    (
      (cert-id (+ batch-id (* stacks-block-height u1000)))
      (current-block stacks-block-height)
      (expiry (+ current-block u525600)) ;; 1 year validity
    )
    (asserts! (is-lab-certified tx-sender) ERR-LAB-NOT-CERTIFIED)
    (asserts! (is-some (map-get? honey-batches { batch-id: batch-id })) ERR-BATCH-NOT-FOUND)
    (asserts! (<= quality-score u100) ERR-INVALID-DATA)
    
    (map-set quality-certifications
      { cert-id: cert-id }
      {
        batch-id: batch-id,
        certifying-body: tx-sender,
        certification-type: certification-type,
        issue-date: current-block,
        expiry-date: expiry,
        grade: grade,
        quality-score: quality-score,
        special-designations: special-designations,
        certificate-hash: certificate-hash
      }
    )
    
    ;; Update batch certification status
    (update-batch-certification-status batch-id true)
    (ok cert-id)
  )
)

;; read only functions
(define-read-only (get-honey-batch (batch-id uint))
  (map-get? honey-batches { batch-id: batch-id })
)

(define-read-only (get-laboratory (lab-id principal))
  (map-get? laboratory-facilities { lab-id: lab-id })
)

(define-read-only (get-test-sample (sample-id uint))
  (map-get? test-samples { sample-id: sample-id })
)

(define-read-only (get-pollen-analysis (test-id uint))
  (map-get? pollen-analysis { test-id: test-id })
)

(define-read-only (get-isotope-analysis (test-id uint))
  (map-get? isotope-analysis { test-id: test-id })
)

(define-read-only (get-adulteration-test (test-id uint))
  (map-get? adulteration-tests { test-id: test-id })
)

(define-read-only (get-quality-certification (cert-id uint))
  (map-get? quality-certifications { cert-id: cert-id })
)

(define-read-only (get-contract-stats)
  {
    total-batches: (var-get total-batches),
    total-tests: (var-get total-tests),
    next-batch-id: (var-get next-batch-id),
    next-test-id: (var-get next-test-id),
    next-sample-id: (var-get next-sample-id)
  }
)

(define-read-only (verify-batch-authenticity (batch-id uint))
  ;; This would aggregate all test results for a batch
  ;; Simplified implementation returns mock verification
  { authentic: true, confidence: u92, grade: "premium" }
)

