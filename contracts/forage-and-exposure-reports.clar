;; title: forage-and-exposure-reports
;; version: 1.0.0
;; summary: Records of forage sources and pesticide exposure incidents
;; description: Track environmental conditions, forage availability, and pesticide exposure events

;; constants
(define-constant ERR-NOT-AUTHORIZED (err u200))
(define-constant ERR-INVALID-DATA (err u201))
(define-constant ERR-REPORT-NOT-FOUND (err u202))
(define-constant ERR-APIARY-NOT-FOUND (err u203))
(define-constant ERR-DUPLICATE-REPORT (err u204))
(define-constant ERR-FUTURE-DATE (err u205))
(define-constant CONTRACT-OWNER tx-sender)

;; data vars
(define-data-var next-forage-report-id uint u1)
(define-data-var next-exposure-report-id uint u1)
(define-data-var total-forage-reports uint u0)
(define-data-var total-exposure-incidents uint u0)

;; data maps
(define-map forage-reports
  { report-id: uint }
  {
    apiary-id: uint,
    reporter: principal,
    location-coordinates: (string-ascii 64),
    forage-type: (string-ascii 32),
    plant-species: (string-ascii 128),
    bloom-period-start: uint,
    bloom-period-end: uint,
    nectar-quality: uint,
    pollen-availability: uint,
    distance-from-apiary: uint,
    report-date: uint,
    seasonal-notes: (string-ascii 256),
    verified: bool
  }
)

(define-map exposure-incidents
  { incident-id: uint }
  {
    apiary-id: uint,
    reporter: principal,
    incident-date: uint,
    chemical-name: (string-ascii 64),
    application-method: (string-ascii 32),
    affected-area: (string-ascii 128),
    distance-from-hives: uint,
    severity-level: uint,
    bee-mortality-observed: bool,
    symptoms-reported: (string-ascii 256),
    treatment-applied: (string-ascii 128),
    recovery-time: uint,
    report-date: uint,
    verified: bool,
    regulatory-reported: bool
  }
)

(define-map seasonal-forage-calendar
  { apiary-id: uint, season: (string-ascii 16) }
  {
    primary-sources: (string-ascii 256),
    secondary-sources: (string-ascii 256),
    risk-factors: (string-ascii 256),
    expected-yield: uint,
    last-updated: uint
  }
)

(define-map environmental-assessments
  { assessment-id: uint }
  {
    apiary-id: uint,
    assessor: principal,
    assessment-date: uint,
    habitat-quality: uint,
    biodiversity-score: uint,
    pesticide-risk-level: uint,
    recommended-actions: (string-ascii 512),
    next-assessment-due: uint
  }
)

;; private functions
(define-private (min (a uint) (b uint))
  (if (<= a b) a b)
)

(define-private (is-valid-coordinates (coordinates (string-ascii 64)))
  (and
    (> (len coordinates) u10)
    (<= (len coordinates) u64)
  )
)

(define-private (is-valid-date-range (start-date uint) (end-date uint))
  (and
    (<= start-date stacks-block-height)
    (>= end-date start-date)
    (<= end-date (+ stacks-block-height u52560)) ;; Max 1 year in future
  )
)

(define-private (calculate-risk-score (severity uint) (distance uint) (mortality bool))
  (let
    (
      (base-score severity)
      (distance-factor (if (<= distance u100) u20 (if (<= distance u500) u10 u5)))
      (mortality-factor (if mortality u30 u0))
    )
    (min (+ base-score distance-factor mortality-factor) u100)
  )
)

(define-private (is-authorized-reporter (apiary-id uint) (reporter principal))
  ;; In a real implementation, this would check apiary ownership or authorized reporters
  true ;; Simplified for this example
)

(define-private (update-seasonal-calendar (apiary-id uint) (forage-type (string-ascii 32)) (plant-species (string-ascii 128)))
  (let
    (
      (current-season (get-current-season))
    )
    (match (map-get? seasonal-forage-calendar { apiary-id: apiary-id, season: current-season })
      existing-data
        (map-set seasonal-forage-calendar
          { apiary-id: apiary-id, season: current-season }
        (merge existing-data { last-updated: stacks-block-height })
        )
      (map-set seasonal-forage-calendar
        { apiary-id: apiary-id, season: current-season }
        {
          primary-sources: plant-species,
          secondary-sources: "",
          risk-factors: "",
          expected-yield: u50,
          last-updated: stacks-block-height
        }
      )
    )
  )
)

(define-private (get-current-season)
  ;; Simplified season calculation based on block height
  (let ((season-block (mod stacks-block-height u210240))) ;; Roughly 4 seasons per year
    (if (< season-block u52560) "spring"
    (if (< season-block u105120) "summer"
    (if (< season-block u157680) "autumn"
    "winter")))
  )
)

;; public functions
(define-public (submit-forage-report 
    (apiary-id uint)
    (location-coordinates (string-ascii 64))
    (forage-type (string-ascii 32))
    (plant-species (string-ascii 128))
    (bloom-start uint)
    (bloom-end uint)
    (nectar-quality uint)
    (pollen-availability uint)
    (distance uint)
    (seasonal-notes (string-ascii 256))
  )
  (let
    (
      (report-id (var-get next-forage-report-id))
      (current-block stacks-block-height)
    )
    (asserts! (is-authorized-reporter apiary-id tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (is-valid-coordinates location-coordinates) ERR-INVALID-DATA)
    (asserts! (is-valid-date-range bloom-start bloom-end) ERR-INVALID-DATA)
    (asserts! (> (len forage-type) u0) ERR-INVALID-DATA)
    (asserts! (> (len plant-species) u0) ERR-INVALID-DATA)
    (asserts! (<= nectar-quality u10) ERR-INVALID-DATA)
    (asserts! (<= pollen-availability u10) ERR-INVALID-DATA)
    (asserts! (<= distance u10000) ERR-INVALID-DATA)
    
    (map-set forage-reports
      { report-id: report-id }
      {
        apiary-id: apiary-id,
        reporter: tx-sender,
        location-coordinates: location-coordinates,
        forage-type: forage-type,
        plant-species: plant-species,
        bloom-period-start: bloom-start,
        bloom-period-end: bloom-end,
        nectar-quality: nectar-quality,
        pollen-availability: pollen-availability,
        distance-from-apiary: distance,
        report-date: current-block,
        seasonal-notes: seasonal-notes,
        verified: false
      }
    )
    
    ;; Update seasonal calendar
    (update-seasonal-calendar apiary-id forage-type plant-species)
    
    (var-set next-forage-report-id (+ report-id u1))
    (var-set total-forage-reports (+ (var-get total-forage-reports) u1))
    (ok report-id)
  )
)

(define-public (report-exposure-incident
    (apiary-id uint)
    (incident-date uint)
    (chemical-name (string-ascii 64))
    (application-method (string-ascii 32))
    (affected-area (string-ascii 128))
    (distance uint)
    (severity uint)
    (bee-mortality bool)
    (symptoms (string-ascii 256))
    (treatment (string-ascii 128))
    (recovery-time uint)
  )
  (let
    (
      (incident-id (var-get next-exposure-report-id))
      (current-block stacks-block-height)
      (risk-score (calculate-risk-score severity distance bee-mortality))
    )
    (asserts! (is-authorized-reporter apiary-id tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (<= incident-date current-block) ERR-FUTURE-DATE)
    (asserts! (> (len chemical-name) u0) ERR-INVALID-DATA)
    (asserts! (<= severity u10) ERR-INVALID-DATA)
    (asserts! (<= distance u10000) ERR-INVALID-DATA)
    
    (map-set exposure-incidents
      { incident-id: incident-id }
      {
        apiary-id: apiary-id,
        reporter: tx-sender,
        incident-date: incident-date,
        chemical-name: chemical-name,
        application-method: application-method,
        affected-area: affected-area,
        distance-from-hives: distance,
        severity-level: severity,
        bee-mortality-observed: bee-mortality,
        symptoms-reported: symptoms,
        treatment-applied: treatment,
        recovery-time: recovery-time,
        report-date: current-block,
        verified: false,
        regulatory-reported: (>= risk-score u70)
      }
    )
    
    (var-set next-exposure-report-id (+ incident-id u1))
    (var-set total-exposure-incidents (+ (var-get total-exposure-incidents) u1))
    (ok incident-id)
  )
)

(define-public (conduct-environmental-assessment
    (apiary-id uint)
    (habitat-quality uint)
    (biodiversity-score uint)
    (pesticide-risk uint)
    (recommendations (string-ascii 512))
  )
  (let
    (
      (assessment-id (+ (* apiary-id u1000) stacks-block-height)) ;; Simple ID generation
      (current-block stacks-block-height)
      (next-due (+ current-block u26280)) ;; 6 months
    )
    (asserts! (is-authorized-reporter apiary-id tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (and (<= habitat-quality u100) (<= biodiversity-score u100) (<= pesticide-risk u100)) ERR-INVALID-DATA)
    
    (map-set environmental-assessments
      { assessment-id: assessment-id }
      {
        apiary-id: apiary-id,
        assessor: tx-sender,
        assessment-date: current-block,
        habitat-quality: habitat-quality,
        biodiversity-score: biodiversity-score,
        pesticide-risk-level: pesticide-risk,
        recommended-actions: recommendations,
        next-assessment-due: next-due
      }
    )
    (ok assessment-id)
  )
)

(define-public (verify-forage-report (report-id uint) (verified bool))
  (match (map-get? forage-reports { report-id: report-id })
    report-data
      (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
        (map-set forage-reports
          { report-id: report-id }
          (merge report-data { verified: verified })
        )
        (ok true)
      )
    ERR-REPORT-NOT-FOUND
  )
)

(define-public (verify-exposure-incident (incident-id uint) (verified bool))
  (match (map-get? exposure-incidents { incident-id: incident-id })
    incident-data
      (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
        (map-set exposure-incidents
          { incident-id: incident-id }
          (merge incident-data { verified: verified })
        )
        (ok true)
      )
    ERR-REPORT-NOT-FOUND
  )
)

;; read only functions
(define-read-only (get-forage-report (report-id uint))
  (map-get? forage-reports { report-id: report-id })
)

(define-read-only (get-exposure-incident (incident-id uint))
  (map-get? exposure-incidents { incident-id: incident-id })
)

(define-read-only (get-seasonal-calendar (apiary-id uint) (season (string-ascii 16)))
  (map-get? seasonal-forage-calendar { apiary-id: apiary-id, season: season })
)

(define-read-only (get-environmental-assessment (assessment-id uint))
  (map-get? environmental-assessments { assessment-id: assessment-id })
)

(define-read-only (get-contract-stats)
  {
    total-forage-reports: (var-get total-forage-reports),
    total-exposure-incidents: (var-get total-exposure-incidents),
    next-forage-report-id: (var-get next-forage-report-id),
    next-exposure-report-id: (var-get next-exposure-report-id)
  }
)

(define-read-only (calculate-apiary-risk-level (apiary-id uint))
  ;; This would typically aggregate all exposure incidents for an apiary
  ;; Simplified implementation returns a mock risk level
  u25 ;; Low risk by default
)

