;; Insurance Entity Verification Contract
;; Validates and manages innovative insurance entities

(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_ENTITY_EXISTS (err u101))
(define-constant ERR_ENTITY_NOT_FOUND (err u102))
(define-constant ERR_INVALID_STATUS (err u103))

;; Entity verification statuses
(define-constant STATUS_PENDING u0)
(define-constant STATUS_VERIFIED u1)
(define-constant STATUS_REJECTED u2)
(define-constant STATUS_SUSPENDED u3)

;; Data structures
(define-map insurance-entities
  { entity-id: uint }
  {
    name: (string-ascii 100),
    license-number: (string-ascii 50),
    status: uint,
    verification-date: uint,
    verifier: principal,
    capital-requirement: uint,
    risk-score: uint
  }
)

(define-map entity-principals
  { principal: principal }
  { entity-id: uint }
)

(define-data-var next-entity-id uint u1)

;; Register a new insurance entity
(define-public (register-entity (name (string-ascii 100)) (license-number (string-ascii 50)) (capital-requirement uint))
  (let ((entity-id (var-get next-entity-id)))
    (asserts! (is-none (map-get? entity-principals { principal: tx-sender })) ERR_ENTITY_EXISTS)
    (map-set insurance-entities
      { entity-id: entity-id }
      {
        name: name,
        license-number: license-number,
        status: STATUS_PENDING,
        verification-date: block-height,
        verifier: CONTRACT_OWNER,
        capital-requirement: capital-requirement,
        risk-score: u50
      }
    )
    (map-set entity-principals { principal: tx-sender } { entity-id: entity-id })
    (var-set next-entity-id (+ entity-id u1))
    (ok entity-id)
  )
)

;; Verify an insurance entity (admin only)
(define-public (verify-entity (entity-id uint) (new-status uint))
  (let ((entity (unwrap! (map-get? insurance-entities { entity-id: entity-id }) ERR_ENTITY_NOT_FOUND)))
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (<= new-status STATUS_SUSPENDED) ERR_INVALID_STATUS)
    (map-set insurance-entities
      { entity-id: entity-id }
      (merge entity {
        status: new-status,
        verification-date: block-height,
        verifier: tx-sender
      })
    )
    (ok true)
  )
)

;; Update entity risk score
(define-public (update-risk-score (entity-id uint) (new-risk-score uint))
  (let ((entity (unwrap! (map-get? insurance-entities { entity-id: entity-id }) ERR_ENTITY_NOT_FOUND)))
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (<= new-risk-score u100) ERR_INVALID_STATUS)
    (map-set insurance-entities
      { entity-id: entity-id }
      (merge entity { risk-score: new-risk-score })
    )
    (ok true)
  )
)

;; Get entity information
(define-read-only (get-entity (entity-id uint))
  (map-get? insurance-entities { entity-id: entity-id })
)

;; Check if entity is verified
(define-read-only (is-entity-verified (entity-id uint))
  (match (map-get? insurance-entities { entity-id: entity-id })
    entity (is-eq (get status entity) STATUS_VERIFIED)
    false
  )
)

;; Get entity by principal
(define-read-only (get-entity-by-principal (principal principal))
  (match (map-get? entity-principals { principal: principal })
    entity-data (map-get? insurance-entities { entity-id: (get entity-id entity-data) })
    none
  )
)
