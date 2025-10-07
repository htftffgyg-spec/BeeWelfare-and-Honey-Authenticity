;; title: hive-health-telemetry
;; version: 1.0.0
;; summary: Sensor attestations for temperature, humidity, and hive weight
;; description: Automated collection and verification of hive health telemetry data

;; constants
(define-constant ERR-NOT-AUTHORIZED (err u300))
(define-constant ERR-INVALID-DATA (err u301))
(define-constant ERR-SENSOR-NOT-REGISTERED (err u302))
(define-constant ERR-READING-NOT-FOUND (err u303))
(define-constant ERR-THRESHOLD-EXCEEDED (err u304))
(define-constant ERR-DEVICE-MALFUNCTION (err u305))
(define-constant CONTRACT-OWNER tx-sender)

;; Temperature thresholds (in Fahrenheit)
(define-constant MIN-TEMP u32)
(define-constant MAX-TEMP u95)
(define-constant OPTIMAL-TEMP-MIN u90)
(define-constant OPTIMAL-TEMP-MAX u95)

;; Humidity thresholds (percentage)
(define-constant MIN-HUMIDITY u45)
(define-constant MAX-HUMIDITY u65)

;; Weight change thresholds (pounds)
(define-constant CRITICAL-WEIGHT-LOSS u20)
(define-constant SIGNIFICANT-WEIGHT-GAIN u15)

;; data vars
(define-data-var next-reading-id uint u1)
(define-data-var next-device-id uint u1)
(define-data-var total-readings uint u0)
(define-data-var total-alerts uint u0)

;; data maps
(define-map sensor-devices
  { device-id: uint }
  {
    apiary-id: uint,
    hive-number: uint,
    device-type: (string-ascii 32),
    manufacturer: (string-ascii 64),
    firmware-version: (string-ascii 16),
    installation-date: uint,
    last-calibration: uint,
    is-active: bool,
    owner: principal,
    accuracy-rating: uint
  }
)

(define-map telemetry-readings
  { reading-id: uint }
  {
    device-id: uint,
    apiary-id: uint,
    hive-number: uint,
    timestamp: uint,
    temperature: uint,
    humidity: uint,
    weight: uint,
    vibration-level: uint,
    sound-level: uint,
    battery-level: uint,
    data-integrity-hash: (string-ascii 64),
    verified: bool
  }
)

(define-map health-alerts
  { alert-id: uint }
  {
    device-id: uint,
    apiary-id: uint,
    alert-type: (string-ascii 32),
    severity: uint,
    trigger-value: uint,
    threshold-breached: uint,
    alert-message: (string-ascii 256),
    timestamp: uint,
    acknowledged: bool,
    resolved: bool
  }
)

(define-map daily-summaries
  { apiary-id: uint, date: uint }
  {
    avg-temperature: uint,
    avg-humidity: uint,
    weight-change: int,
    readings-count: uint,
    alerts-count: uint,
    health-score: uint,
    notes: (string-ascii 256)
  }
)

(define-map device-calibrations
  { device-id: uint, calibration-date: uint }
  {
    calibrator: principal,
    temperature-offset: int,
    humidity-offset: int,
    weight-offset: int,
    calibration-notes: (string-ascii 256),
    next-calibration-due: uint
  }
)

;; private functions
(define-private (min (a uint) (b uint))
  (if (<= a b) a b)
)

(define-private (is-valid-temperature (temp uint))
  (and (>= temp u10) (<= temp u120)) ;; Reasonable range in Fahrenheit
)

(define-private (is-valid-humidity (humidity uint))
  (and (>= humidity u0) (<= humidity u100))
)

(define-private (is-valid-weight (weight uint))
  (and (>= weight u0) (<= weight u500)) ;; Max 500 lbs for a hive
)

(define-private (check-temperature-alert (device-id uint) (temp uint) (timestamp uint))
  (let
    (
      (severity (if (or (<= temp MIN-TEMP) (>= temp MAX-TEMP)) u5 u3))
    )
    (if (or (< temp MIN-TEMP) (> temp MAX-TEMP))
      (create-alert device-id "temperature" severity temp timestamp "Temperature out of safe range")
      (ok u0)
    )
  )
)

(define-private (check-humidity-alert (device-id uint) (humidity uint) (timestamp uint))
  (let
    (
      (severity (if (or (<= humidity u30) (>= humidity u80)) u4 u2))
    )
    (if (or (< humidity MIN-HUMIDITY) (> humidity MAX-HUMIDITY))
      (create-alert device-id "humidity" severity humidity timestamp "Humidity levels suboptimal")
      (ok u0)
    )
  )
)

(define-private (create-alert (device-id uint) (alert-type (string-ascii 32)) (severity uint) (trigger-value uint) (timestamp uint) (message (string-ascii 256)))
  (let
    (
      (alert-id (+ (var-get total-alerts) u1))
      (device-info (unwrap-panic (map-get? sensor-devices { device-id: device-id })))
    )
    (map-set health-alerts
      { alert-id: alert-id }
      {
        device-id: device-id,
        apiary-id: (get apiary-id device-info),
        alert-type: alert-type,
        severity: severity,
        trigger-value: trigger-value,
        threshold-breached: (if (is-eq alert-type "temperature") (if (< trigger-value MIN-TEMP) MIN-TEMP MAX-TEMP) u0),
        alert-message: message,
        timestamp: timestamp,
        acknowledged: false,
        resolved: false
      }
    )
    (var-set total-alerts alert-id)
    (ok alert-id)
  )
)

(define-private (calculate-health-score (temperature uint) (humidity uint) (weight-stable bool) (battery uint))
  (let
    (
      (temp-score (if (and (>= temperature OPTIMAL-TEMP-MIN) (<= temperature OPTIMAL-TEMP-MAX)) u25 u15))
      (humidity-score (if (and (>= humidity MIN-HUMIDITY) (<= humidity MAX-HUMIDITY)) u25 u15))
      (weight-score (if weight-stable u25 u10))
      (battery-score (if (>= battery u20) u25 u5))
    )
    (+ temp-score humidity-score weight-score battery-score)
  )
)

(define-private (update-daily-summary (apiary-id uint) (temperature uint) (humidity uint) (weight uint))
  (let
    (
      (today (/ stacks-block-height u144)) ;; Roughly daily blocks
      (current-summary (map-get? daily-summaries { apiary-id: apiary-id, date: today }))
    )
    (match current-summary
      existing
        (let
          (
            (new-count (+ (get readings-count existing) u1))
            (new-avg-temp (/ (+ (* (get avg-temperature existing) (- new-count u1)) temperature) new-count))
            (new-avg-humidity (/ (+ (* (get avg-humidity existing) (- new-count u1)) humidity) new-count))
          )
          (map-set daily-summaries
            { apiary-id: apiary-id, date: today }
            (merge existing {
              avg-temperature: new-avg-temp,
              avg-humidity: new-avg-humidity,
              readings-count: new-count
            })
          )
        )
      (map-set daily-summaries
        { apiary-id: apiary-id, date: today }
        {
          avg-temperature: temperature,
          avg-humidity: humidity,
          weight-change: 0,
          readings-count: u1,
          alerts-count: u0,
          health-score: (calculate-health-score temperature humidity true u50),
          notes: ""
        }
      )
    )
  )
)

;; public functions
(define-public (register-sensor-device
    (apiary-id uint)
    (hive-number uint)
    (device-type (string-ascii 32))
    (manufacturer (string-ascii 64))
    (firmware-version (string-ascii 16))
  )
  (let
    (
      (device-id (var-get next-device-id))
      (current-block stacks-block-height)
    )
    (asserts! (> (len device-type) u0) ERR-INVALID-DATA)
    (asserts! (> (len manufacturer) u0) ERR-INVALID-DATA)
    (asserts! (> hive-number u0) ERR-INVALID-DATA)
    
    (map-set sensor-devices
      { device-id: device-id }
      {
        apiary-id: apiary-id,
        hive-number: hive-number,
        device-type: device-type,
        manufacturer: manufacturer,
        firmware-version: firmware-version,
        installation-date: current-block,
        last-calibration: current-block,
        is-active: true,
        owner: tx-sender,
        accuracy-rating: u95
      }
    )
    
    (var-set next-device-id (+ device-id u1))
    (ok device-id)
  )
)

(define-public (submit-telemetry-reading
    (device-id uint)
    (temperature uint)
    (humidity uint)
    (weight uint)
    (vibration uint)
    (sound uint)
    (battery uint)
    (data-hash (string-ascii 64))
  )
  (let
    (
      (reading-id (var-get next-reading-id))
      (current-block stacks-block-height)
      (device-info (unwrap! (map-get? sensor-devices { device-id: device-id }) ERR-SENSOR-NOT-REGISTERED))
    )
    (asserts! (get is-active device-info) ERR-DEVICE-MALFUNCTION)
    (asserts! (is-valid-temperature temperature) ERR-INVALID-DATA)
    (asserts! (is-valid-humidity humidity) ERR-INVALID-DATA)
    (asserts! (is-valid-weight weight) ERR-INVALID-DATA)
    (asserts! (<= vibration u100) ERR-INVALID-DATA)
    (asserts! (<= sound u100) ERR-INVALID-DATA)
    (asserts! (<= battery u100) ERR-INVALID-DATA)
    
    ;; Record the telemetry reading
    (map-set telemetry-readings
      { reading-id: reading-id }
      {
        device-id: device-id,
        apiary-id: (get apiary-id device-info),
        hive-number: (get hive-number device-info),
        timestamp: current-block,
        temperature: temperature,
        humidity: humidity,
        weight: weight,
        vibration-level: vibration,
        sound-level: sound,
        battery-level: battery,
        data-integrity-hash: data-hash,
        verified: false
      }
    )
    
    ;; Check for alerts
    (unwrap-panic (check-temperature-alert device-id temperature current-block))
    (unwrap-panic (check-humidity-alert device-id humidity current-block))
    
    ;; Update daily summary
    (update-daily-summary (get apiary-id device-info) temperature humidity weight)
    
    (var-set next-reading-id (+ reading-id u1))
    (var-set total-readings (+ (var-get total-readings) u1))
    (ok reading-id)
  )
)

(define-public (calibrate-device
    (device-id uint)
    (temp-offset int)
    (humidity-offset int)
    (weight-offset int)
    (notes (string-ascii 256))
  )
  (let
    (
      (current-block stacks-block-height)
      (next-calibration (+ current-block u26280)) ;; 6 months
    )
    (asserts! (is-some (map-get? sensor-devices { device-id: device-id })) ERR-SENSOR-NOT-REGISTERED)
    
    (map-set device-calibrations
      { device-id: device-id, calibration-date: current-block }
      {
        calibrator: tx-sender,
        temperature-offset: temp-offset,
        humidity-offset: humidity-offset,
        weight-offset: weight-offset,
        calibration-notes: notes,
        next-calibration-due: next-calibration
      }
    )
    
    ;; Update device last calibration
    (match (map-get? sensor-devices { device-id: device-id })
      device-info
        (map-set sensor-devices
          { device-id: device-id }
          (merge device-info { last-calibration: current-block })
        )
      false
    )
    (ok true)
  )
)

(define-public (acknowledge-alert (alert-id uint))
  (match (map-get? health-alerts { alert-id: alert-id })
    alert-data
      (begin
        (map-set health-alerts
          { alert-id: alert-id }
          (merge alert-data { acknowledged: true })
        )
        (ok true)
      )
    ERR-READING-NOT-FOUND
  )
)

(define-public (resolve-alert (alert-id uint) (resolution-notes (string-ascii 256)))
  (match (map-get? health-alerts { alert-id: alert-id })
    alert-data
      (begin
        (map-set health-alerts
          { alert-id: alert-id }
          (merge alert-data { resolved: true, acknowledged: true })
        )
        (ok true)
      )
    ERR-READING-NOT-FOUND
  )
)

(define-public (verify-reading (reading-id uint) (verified bool))
  (match (map-get? telemetry-readings { reading-id: reading-id })
    reading-data
      (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
        (map-set telemetry-readings
          { reading-id: reading-id }
          (merge reading-data { verified: verified })
        )
        (ok true)
      )
    ERR-READING-NOT-FOUND
  )
)

(define-public (deactivate-device (device-id uint))
  (match (map-get? sensor-devices { device-id: device-id })
    device-info
      (begin
        (asserts! (is-eq tx-sender (get owner device-info)) ERR-NOT-AUTHORIZED)
        (map-set sensor-devices
          { device-id: device-id }
          (merge device-info { is-active: false })
        )
        (ok true)
      )
    ERR-SENSOR-NOT-REGISTERED
  )
)

;; read only functions
(define-read-only (get-sensor-device (device-id uint))
  (map-get? sensor-devices { device-id: device-id })
)

(define-read-only (get-telemetry-reading (reading-id uint))
  (map-get? telemetry-readings { reading-id: reading-id })
)

(define-read-only (get-health-alert (alert-id uint))
  (map-get? health-alerts { alert-id: alert-id })
)

(define-read-only (get-daily-summary (apiary-id uint) (date uint))
  (map-get? daily-summaries { apiary-id: apiary-id, date: date })
)

(define-read-only (get-device-calibration (device-id uint) (calibration-date uint))
  (map-get? device-calibrations { device-id: device-id, calibration-date: calibration-date })
)

(define-read-only (get-contract-stats)
  {
    total-readings: (var-get total-readings),
    total-alerts: (var-get total-alerts),
    next-reading-id: (var-get next-reading-id),
    next-device-id: (var-get next-device-id)
  }
)

(define-read-only (calculate-hive-health-trend (apiary-id uint) (days uint))
  ;; This would analyze recent daily summaries to calculate health trends
  ;; Simplified implementation returns a mock trend
  { trend: "stable", score: u85, confidence: u90 }
)

