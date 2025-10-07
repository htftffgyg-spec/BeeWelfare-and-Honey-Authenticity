;; title: apiary-certification-registry
;; version: 1.0.0
;; summary: Register apiaries, hive counts, and inspector audits for bee welfare certification
;; description: Comprehensive system for managing apiary registrations, certifications, and compliance audits

;; constants
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-APIARY-EXISTS (err u101))
(define-constant ERR-APIARY-NOT-FOUND (err u102))
(define-constant ERR-INVALID-DATA (err u103))
(define-constant ERR-INSPECTOR-NOT-CERTIFIED (err u104))
(define-constant ERR-AUDIT-NOT-FOUND (err u105))
(define-constant CONTRACT-OWNER tx-sender)

;; data vars
(define-data-var next-apiary-id uint u1)
(define-data-var next-audit-id uint u1)
(define-data-var total-apiaries uint u0)
(define-data-var total-audits uint u0)

;; data maps
(define-map apiaries
  { apiary-id: uint }
  {
    owner: principal,
    name: (string-ascii 128),
    location: (string-ascii 256),
    hive-count: uint,
    certification-level: (string-ascii 32),
    registration-date: uint,
    last-inspection: uint,
    is-active: bool
  }
)

(define-map inspectors
  { inspector-id: principal }
  {
    name: (string-ascii 128),
    certification: (string-ascii 64),
    license-expiry: uint,
    is-certified: bool,
    audit-count: uint
  }
)

(define-map audits
  { audit-id: uint }
  {
    apiary-id: uint,
    inspector-id: principal,
    audit-date: uint,
    compliance-score: uint,
    findings: (string-ascii 512),
    recommendations: (string-ascii 512),
    certification-renewed: bool,
    next-audit-due: uint
  }
)

;; private functions
(define-private (is-valid-apiary-data (name (string-ascii 128)) (location (string-ascii 256)) (hive-count uint))
  (and
    (> (len name) u0)
    (> (len location) u0)
    (> hive-count u0)
    (<= hive-count u10000)
  )
)

(define-private (is-inspector-authorized (inspector principal))
  (match (map-get? inspectors { inspector-id: inspector })
    inspector-data (get is-certified inspector-data)
    false
  )
)

(define-private (calculate-next-audit-date (compliance-score uint))
  (if (>= compliance-score u85)
    (+ stacks-block-height u52560) ;; 1 year for high compliance
    (if (>= compliance-score u70)
      (+ stacks-block-height u26280) ;; 6 months for medium compliance
      (+ stacks-block-height u13140) ;; 3 months for low compliance
    )
  )
)

(define-private (update-apiary-last-inspection (apiary-id uint) (audit-date uint))
  (match (map-get? apiaries { apiary-id: apiary-id })
    apiary-data
        (map-set apiaries
          { apiary-id: apiary-id }
          (merge apiary-data { last-inspection: audit-date })
        )
    false
  )
)

;; public functions
(define-public (register-apiary (name (string-ascii 128)) (location (string-ascii 256)) (hive-count uint))
  (let
    (
      (apiary-id (var-get next-apiary-id))
      (current-block stacks-block-height)
    )
    (asserts! (is-valid-apiary-data name location hive-count) ERR-INVALID-DATA)
    (asserts! (is-none (map-get? apiaries { apiary-id: apiary-id })) ERR-APIARY-EXISTS)
    
    (map-set apiaries
      { apiary-id: apiary-id }
      {
        owner: tx-sender,
        name: name,
        location: location,
        hive-count: hive-count,
        certification-level: "pending",
        registration-date: current-block,
        last-inspection: u0,
        is-active: true
      }
    )
    
    (var-set next-apiary-id (+ apiary-id u1))
    (var-set total-apiaries (+ (var-get total-apiaries) u1))
    (ok apiary-id)
  )
)

(define-public (register-inspector (inspector principal) (name (string-ascii 128)) (certification (string-ascii 64)) (license-expiry uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (> (len name) u0) ERR-INVALID-DATA)
    (asserts! (> license-expiry stacks-block-height) ERR-INVALID-DATA)
    
    (map-set inspectors
      { inspector-id: inspector }
      {
        name: name,
        certification: certification,
        license-expiry: license-expiry,
        is-certified: true,
        audit-count: u0
      }
    )
    (ok true)
  )
)

(define-public (conduct-audit (apiary-id uint) (compliance-score uint) (findings (string-ascii 512)) (recommendations (string-ascii 512)))
  (let
    (
      (audit-id (var-get next-audit-id))
      (current-block stacks-block-height)
      (next-audit (calculate-next-audit-date compliance-score))
      (certification-renewed (>= compliance-score u70))
    )
    (asserts! (is-inspector-authorized tx-sender) ERR-INSPECTOR-NOT-CERTIFIED)
    (asserts! (is-some (map-get? apiaries { apiary-id: apiary-id })) ERR-APIARY-NOT-FOUND)
    (asserts! (<= compliance-score u100) ERR-INVALID-DATA)
    
    ;; Record the audit
    (map-set audits
      { audit-id: audit-id }
      {
        apiary-id: apiary-id,
        inspector-id: tx-sender,
        audit-date: current-block,
        compliance-score: compliance-score,
        findings: findings,
        recommendations: recommendations,
        certification-renewed: certification-renewed,
        next-audit-due: next-audit
      }
    )
    
    ;; Update apiary last inspection date
    (update-apiary-last-inspection apiary-id current-block)
    
    ;; Update certification level based on compliance score
    (unwrap-panic (update-apiary-certification apiary-id compliance-score))
    
    ;; Update inspector audit count
    (unwrap-panic (update-inspector-audit-count tx-sender))
    
    (var-set next-audit-id (+ audit-id u1))
    (var-set total-audits (+ (var-get total-audits) u1))
    (ok audit-id)
  )
)

(define-public (update-apiary-certification (apiary-id uint) (compliance-score uint))
  (match (map-get? apiaries { apiary-id: apiary-id })
    apiary-data
      (let
        (
          (new-level
            (if (>= compliance-score u90) "premium"
            (if (>= compliance-score u75) "standard"
            (if (>= compliance-score u60) "basic"
            "non-compliant")))
          )
        )
        (map-set apiaries
          { apiary-id: apiary-id }
          (merge apiary-data { certification-level: new-level })
        )
        (ok new-level)
      )
    ERR-APIARY-NOT-FOUND
  )
)

(define-public (update-inspector-audit-count (inspector principal))
  (match (map-get? inspectors { inspector-id: inspector })
    inspector-data
      (begin
        (map-set inspectors
          { inspector-id: inspector }
          (merge inspector-data { audit-count: (+ (get audit-count inspector-data) u1) })
        )
        (ok true)
      )
    ERR-INSPECTOR-NOT-CERTIFIED
  )
)

(define-public (update-hive-count (apiary-id uint) (new-hive-count uint))
  (match (map-get? apiaries { apiary-id: apiary-id })
    apiary-data
      (begin
        (asserts! (is-eq tx-sender (get owner apiary-data)) ERR-NOT-AUTHORIZED)
        (asserts! (and (> new-hive-count u0) (<= new-hive-count u10000)) ERR-INVALID-DATA)
        
        (map-set apiaries
          { apiary-id: apiary-id }
          (merge apiary-data { hive-count: new-hive-count })
        )
        (ok true)
      )
    ERR-APIARY-NOT-FOUND
  )
)

(define-public (deactivate-apiary (apiary-id uint))
  (match (map-get? apiaries { apiary-id: apiary-id })
    apiary-data
      (begin
        (asserts! (is-eq tx-sender (get owner apiary-data)) ERR-NOT-AUTHORIZED)
        
        (map-set apiaries
          { apiary-id: apiary-id }
          (merge apiary-data { is-active: false })
        )
        (ok true)
      )
    ERR-APIARY-NOT-FOUND
  )
)

;; read only functions
(define-read-only (get-apiary-info (apiary-id uint))
  (map-get? apiaries { apiary-id: apiary-id })
)

(define-read-only (get-inspector-info (inspector principal))
  (map-get? inspectors { inspector-id: inspector })
)

(define-read-only (get-audit-info (audit-id uint))
  (map-get? audits { audit-id: audit-id })
)

(define-read-only (get-contract-stats)
  {
    total-apiaries: (var-get total-apiaries),
    total-audits: (var-get total-audits),
    next-apiary-id: (var-get next-apiary-id),
    next-audit-id: (var-get next-audit-id)
  }
)

(define-read-only (is-apiary-compliant (apiary-id uint))
  (match (map-get? apiaries { apiary-id: apiary-id })
    apiary-data
      (let ((cert-level (get certification-level apiary-data)))
        (not (is-eq cert-level "non-compliant"))
      )
    false
  )
)

