;; Customer Experience Contract
;; Enhances insurance interactions and customer satisfaction

(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u500))
(define-constant ERR_CUSTOMER_NOT_FOUND (err u501))
(define-constant ERR_INVALID_RATING (err u502))
(define-constant ERR_INVALID_PARAMETERS (err u503))

;; Customer interaction types
(define-constant INTERACTION_INQUIRY u1)
(define-constant INTERACTION_COMPLAINT u2)
(define-constant INTERACTION_CLAIM u3)
(define-constant INTERACTION_FEEDBACK u4)

;; Data structures
(define-map customer-profiles
  { customer: principal }
  {
    registration-date: uint,
    total-policies: uint,
    total-claims: uint,
    satisfaction-score: uint,
    loyalty-points: uint,
    preferred-communication: uint,
    risk-profile: uint
  }
)

(define-map customer-interactions
  { interaction-id: uint }
  {
    customer: principal,
    interaction-type: uint,
    description: (string-ascii 200),
    priority: uint,
    status: uint,
    resolution-time: (optional uint),
    satisfaction-rating: (optional uint),
    timestamp: uint
  }
)

(define-map customer-feedback
  { feedback-id: uint }
  {
    customer: principal,
    product-id: (optional uint),
    rating: uint,
    comments: (string-ascii 300),
    category: uint,
    timestamp: uint,
    helpful-votes: uint
  }
)

(define-data-var next-interaction-id uint u1)
(define-data-var next-feedback-id uint u1)

;; Register customer profile
(define-public (register-customer (preferred-communication uint))
  (let ((existing-profile (map-get? customer-profiles { customer: tx-sender })))
    (asserts! (is-none existing-profile) ERR_INVALID_PARAMETERS)
    (map-set customer-profiles
      { customer: tx-sender }
      {
        registration-date: block-height,
        total-policies: u0,
        total-claims: u0,
        satisfaction-score: u80,
        loyalty-points: u100,
        preferred-communication: preferred-communication,
        risk-profile: u50
      }
    )
    (ok true)
  )
)

;; Create customer interaction
(define-public (create-interaction
  (interaction-type uint)
  (description (string-ascii 200))
  (priority uint))
  (let ((interaction-id (var-get next-interaction-id)))
    (asserts! (<= interaction-type INTERACTION_FEEDBACK) ERR_INVALID_PARAMETERS)
    (asserts! (<= priority u5) ERR_INVALID_PARAMETERS)

    (map-set customer-interactions
      { interaction-id: interaction-id }
      {
        customer: tx-sender,
        interaction-type: interaction-type,
        description: description,
        priority: priority,
        status: u0,
        resolution-time: none,
        satisfaction-rating: none,
        timestamp: block-height
      }
    )
    (var-set next-interaction-id (+ interaction-id u1))
    (ok interaction-id)
  )
)

;; Resolve customer interaction
(define-public (resolve-interaction (interaction-id uint) (satisfaction-rating uint))
  (let ((interaction (unwrap! (map-get? customer-interactions { interaction-id: interaction-id }) ERR_CUSTOMER_NOT_FOUND)))
    (asserts! (is-eq tx-sender (get customer interaction)) ERR_UNAUTHORIZED)
    (asserts! (<= satisfaction-rating u5) ERR_INVALID_RATING)

    (map-set customer-interactions
      { interaction-id: interaction-id }
      (merge interaction {
        status: u1,
        resolution-time: (some (- block-height (get timestamp interaction))),
        satisfaction-rating: (some satisfaction-rating)
      })
    )

    ;; Update customer satisfaction score
    (try! (update-customer-satisfaction tx-sender satisfaction-rating))
    (ok true)
  )
)

;; Submit customer feedback
(define-public (submit-feedback
  (product-id (optional uint))
  (rating uint)
  (comments (string-ascii 300))
  (category uint))
  (let ((feedback-id (var-get next-feedback-id)))
    (asserts! (<= rating u5) ERR_INVALID_RATING)
    (asserts! (> rating u0) ERR_INVALID_RATING)

    (map-set customer-feedback
      { feedback-id: feedback-id }
      {
        customer: tx-sender,
        product-id: product-id,
        rating: rating,
        comments: comments,
        category: category,
        timestamp: block-height,
        helpful-votes: u0
      }
    )
    (var-set next-feedback-id (+ feedback-id u1))
    (ok feedback-id)
  )
)

;; Update customer satisfaction score
(define-private (update-customer-satisfaction (customer principal) (new-rating uint))
  (let ((profile (unwrap! (map-get? customer-profiles { customer: customer }) ERR_CUSTOMER_NOT_FOUND)))
    (let ((current-score (get satisfaction-score profile))
          (new-score (/ (+ (* current-score u9) (* new-rating u20)) u10)))
      (map-set customer-profiles
        { customer: customer }
        (merge profile { satisfaction-score: new-score })
      )
      (ok true)
    )
  )
)

;; Award loyalty points
(define-public (award-loyalty-points (customer principal) (points uint))
  (let ((profile (unwrap! (map-get? customer-profiles { customer: customer }) ERR_CUSTOMER_NOT_FOUND)))
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (map-set customer-profiles
      { customer: customer }
      (merge profile {
        loyalty-points: (+ (get loyalty-points profile) points)
      })
    )
    (ok true)
  )
)

;; Update customer policy count
(define-public (update-policy-count (customer principal) (increment bool))
  (let ((profile (unwrap! (map-get? customer-profiles { customer: customer }) ERR_CUSTOMER_NOT_FOUND)))
    (map-set customer-profiles
      { customer: customer }
      (merge profile {
        total-policies: (if increment
          (+ (get total-policies profile) u1)
          (if (> (get total-policies profile) u0)
            (- (get total-policies profile) u1)
            u0
          )
        )
      })
    )
    (ok true)
  )
)

;; Vote on feedback helpfulness
(define-public (vote-feedback-helpful (feedback-id uint))
  (let ((feedback (unwrap! (map-get? customer-feedback { feedback-id: feedback-id }) ERR_CUSTOMER_NOT_FOUND)))
    (map-set customer-feedback
      { feedback-id: feedback-id }
      (merge feedback {
        helpful-votes: (+ (get helpful-votes feedback) u1)
      })
    )
    (ok true)
  )
)

;; Get customer profile
(define-read-only (get-customer-profile (customer principal))
  (map-get? customer-profiles { customer: customer })
)

;; Get interaction details
(define-read-only (get-interaction (interaction-id uint))
  (map-get? customer-interactions { interaction-id: interaction-id })
)

;; Get feedback details
(define-read-only (get-feedback (feedback-id uint))
  (map-get? customer-feedback { feedback-id: feedback-id })
)

;; Calculate customer loyalty tier
(define-read-only (get-loyalty-tier (customer principal))
  (match (map-get? customer-profiles { customer: customer })
    profile
      (let ((points (get loyalty-points profile)))
        (if (>= points u1000) u4
          (if (>= points u500) u3
            (if (>= points u200) u2 u1)
          )
        )
      )
    u0
  )
)
