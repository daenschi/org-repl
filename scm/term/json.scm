;;; term/json.scm — JSON reader/writer in pure Scheme.
;;;
;;; Why not Guile's stdlib (json)? Two reasons:
;;;   1. (json) appeared in Guile 3.0.9; we support 3.0.8 (Debian bookworm).
;;;   2. This module must also compile under Hoot (Scheme→wasm) later, where
;;;      we can only rely on a small portable core. No dependencies, no I/O.
;;;
;;; Data model (mirrors the graph JSON we already use):
;;;   object  → alist with STRING keys:  '(("a" . 1) ("b" . 2))
;;;   array   → vector:                  #(1 2 3)
;;;   string  → string, number → number, true/false → #t/#f, null → the symbol null
;;;
;;; API:
;;;   (json-read-string s)   → scheme value
;;;   (json-write-string x)  → string

(define-module (term json)
  #:use-module (srfi srfi-1)
  #:export (json-read-string json-write-string))

;;; --- writing ---------------------------------------------------------------

(define (json-write-string x)
  (call-with-output-string
   (lambda (port) (write-json x port))))

(define (write-json x port)
  (cond
   ((eq? x #t) (display "true" port))
   ((eq? x #f) (display "false" port))
   ((eq? x 'null) (display "null" port))
   ((string? x) (write-json-string x port))
   ((number? x) (display (number->string x) port))
   ((vector? x)
    (display "[" port)
    (let loop ((i 0))
      (when (< i (vector-length x))
        (when (> i 0) (display "," port))
        (write-json (vector-ref x i) port)
        (loop (+ i 1))))
    (display "]" port))
   ;; alist = object. A pair whose car is a string is an object entry.
   ((and (list? x) (every pair? x))
    (display "{" port)
    (let loop ((xs x) (first? #t))
      (unless (null? xs)
        (unless first? (display "," port))
        (write-json-string (caar xs) port)
        (display ":" port)
        (write-json (cdar xs) port)
        (loop (cdr xs) #f)))
    (display "}" port))
   (else (error "json-write: unsupported value" x))))

(define (write-json-string s port)
  (display #\" port)
  (string-for-each
   (lambda (c)
     (case c
       ((#\") (display "\\\"" port))
       ((#\\) (display "\\\\" port))
       ((#\newline) (display "\\n" port))
       ((#\tab) (display "\\t" port))
       ((#\return) (display "\\r" port))
       (else (display c port))))
   s)
  (display #\" port))

;;; --- reading ---------------------------------------------------------------
;;; A tiny recursive-descent parser over the string with an index.
;;; Each parse-X returns two values: the value and the next index.

(define (json-read-string s)
  (call-with-values (lambda () (parse-value s (skip-ws s 0)))
    (lambda (value next) value)))

(define (ws? c) (member c '(#\space #\tab #\newline #\return)))

(define (skip-ws s i)
  (if (and (< i (string-length s)) (ws? (string-ref s i)))
      (skip-ws s (+ i 1))
      i))

(define (parse-value s i)
  (let ((c (string-ref s i)))
    (cond
     ((char=? c #\{) (parse-object s (skip-ws s (+ i 1))))
     ((char=? c #\[) (parse-array s (skip-ws s (+ i 1))))
     ((char=? c #\") (parse-string s (+ i 1)))
     ((or (char-numeric? c) (char=? c #\-)) (parse-number s i))
     ((string-prefix-at? s "true" i) (values #t (+ i 4)))
     ((string-prefix-at? s "false" i) (values #f (+ i 5)))
     ((string-prefix-at? s "null" i) (values 'null (+ i 4)))
     (else (error "json-read: unexpected character" c i)))))

(define (string-prefix-at? s prefix i)
  (let ((n (string-length prefix)))
    (and (<= (+ i n) (string-length s))
         (string=? (substring s i (+ i n)) prefix))))

(define (parse-object s i)
  (if (char=? (string-ref s i) #\})
      (values '() (+ i 1))
      (let loop ((i i) (acc '()))
        (call-with-values (lambda () (parse-string s (+ i 1)))
          (lambda (key i2)
            (let* ((i3 (skip-ws s i2))          ; expect ':'
                   (i4 (skip-ws s (+ i3 1))))
              (call-with-values (lambda () (parse-value s i4))
                (lambda (val i5)
                  (let ((i6 (skip-ws s i5))
                        (acc2 (cons (cons key val) acc)))
                    (case (string-ref s i6)
                      ((#\,) (loop (skip-ws s (+ i6 1)) acc2))
                      ((#\}) (values (reverse acc2) (+ i6 1)))
                      (else (error "json-read: expected , or } in object")))))))))))

(define (parse-array s i)
  (if (char=? (string-ref s i) #\])
      (values (vector) (+ i 1))
      (let loop ((i i) (acc '()))
        (call-with-values (lambda () (parse-value s i))
          (lambda (val i2)
            (let ((i3 (skip-ws s i2))
                  (acc2 (cons val acc)))
              (case (string-ref s i3)
                ((#\,) (loop (skip-ws s (+ i3 1)) acc2))
                ((#\]) (values (list->vector (reverse acc2)) (+ i3 1)))
                (else (error "json-read: expected , or ] in array")))))))))

(define (parse-string s i)
  ;; i points just past the opening quote
  (let loop ((i i) (acc '()))
    (let ((c (string-ref s i)))
      (cond
       ((char=? c #\") (values (list->string (reverse acc)) (+ i 1)))
       ((char=? c #\\)
        (let ((e (string-ref s (+ i 1))))
          (case e
            ((#\n) (loop (+ i 2) (cons #\newline acc)))
            ((#\t) (loop (+ i 2) (cons #\tab acc)))
            ((#\r) (loop (+ i 2) (cons #\return acc)))
            ((#\" #\\ #\/) (loop (+ i 2) (cons e acc)))
            ;; \uXXXX: basic plane only, enough for our config strings
            ((#\u)
             (let ((code (string->number (substring s (+ i 2) (+ i 6)) 16)))
               (loop (+ i 6) (cons (integer->char code) acc))))
            (else (error "json-read: bad escape" e)))))
       (else (loop (+ i 1) (cons c acc)))))))

(define (parse-number s i)
  (let loop ((j i))
    (if (and (< j (string-length s))
             (let ((c (string-ref s j)))
               (or (char-numeric? c) (member c '(#\- #\+ #\. #\e #\E)))))
        (loop (+ j 1))
        (values (string->number (substring s i j)) j))))
