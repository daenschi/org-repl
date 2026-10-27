;;; term/types.scm — types as data, terms as values. Pure, no I/O.
;;;
;;; The model, in plain words:
;;;   Base types are PREDICATES on strings: characters, wholenumbers, symbols.
;;;   A composite type is a list of (field-name . type-name) fields — a record
;;;   shape. A term is a list of values, validated field by field.
;;;   Composition goes ONE direction only: a field's type must already exist
;;;   when the type is defined. No forward references, no self reference.
;;;   So the type graph is always a DAG, and every type is defined before use.
;;;
;;; API:
;;;   (define-type! name fields)  → name or (error ...)
;;;   (validate-term name term)   → (ok) or (errors msg ...)
;;;   (render-term name term)     → the term as a display string

(define-module (term types)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-13)
  #:use-module (srfi srfi-14)
  #:export (define-type! validate-term render-term resolve-type
            validate-value all-types reset-registry!))

;;; --- the three primitives ----------------------------------------------------

;;; n-characters: a, b, c, abc, asuihd, ... — letters only, at least one.
(define (characters? s)
  (and (string? s)
       (> (string-length s) 0)
       (string-every char-set:letter s)))

;;; n-wholenumbers: -2, -1, 0, +1, +2, ... — optional sign, then digits.
(define (wholenumber? s)
  (and (string? s)
       (let ((body (if (and (> (string-length s) 0)
                            (member (string-ref s 0) '(#\+ #\-)))
                       (substring s 1)
                       s)))
         (and (> (string-length body) 0)
              (string-every char-set:digit body)))))

;;; n-symbols: ¦ @ # § ! ... — no letters, no digits, no whitespace.
(define (symbols? s)
  (and (string? s)
       (> (string-length s) 0)
       (string-every
        (lambda (c)
          (not (or (char-alphabetic? c)
                   (char-numeric? c)
                   (char-whitespace? c))))
        s)))

;;; The base registry entries: (name . base-predicate).
(define (base-predicate name)
  (cond ((equal? name "characters")    characters?)
        ((equal? name "wholenumbers")  wholenumber?)
        ((equal? name "symbols")       symbols?)
        (else #f)))

;;; --- the registry: which types exist, in definition order --------------------

(define *registry* '())   ; alist (name . fields), newest first
(define (reset-registry!) (set! *registry* '()))

(define (resolve-type name)
  (assoc-ref *registry* name))

(define (all-types) *registry*)

;;; Define a composite type. fields = ((field-name . type-name) ...).
;;; Every field's type must exist ALREADY (base or composite) — that is the
;;; one-direction rule, and it also makes self reference impossible.
(define (define-type! name fields)
  (for-each
   (lambda (f)
     (let ((ftype (cdr f)))
       (cond
        ((equal? ftype name)
         (error "self reference: type" name "cannot contain itself"))
        ((not (or (base-predicate ftype) (resolve-type ftype)))
         (error "undefined type" ftype "— define it before using it in" name)))))
   fields)
  (set! *registry* (cons (cons name fields) *registry*))
  name)

;;; --- validation ---------------------------------------------------------------

;;; A value at a field: base types check the string; composite types recurse.
(define (validate-value ftype value errors)
  (cond
   ((base-predicate ftype)
    (if ((base-predicate ftype) value)
        errors
        (cons (string-append "expected " ftype ", got "
                             (if (string? value) value "<not a string>"))
              errors)))
   ((resolve-type ftype)
    (if (vector? value)
        (append (validate-term ftype value) errors)
        (cons (string-append "expected a " ftype " term") errors)))
   (else (cons (string-append "unknown type " ftype) errors))))

;;; term = a vector of values (JSON array). Arity must match exactly.
;;; Returns '() when valid, else a list of human-readable errors.
(define (validate-term name term)
  (let ((spec (resolve-type name)))
    (cond
     ((not spec)
      (list (string-append "unknown type " name)))
     ((not (vector? term))
      (list "term must be a list of values"))
     ((not (= (vector-length term) (length spec)))
      (list (string-append "arity: " name " takes "
                           (number->string (length spec)) " values, got "
                           (number->string (vector-length term)))))
     (else
      (fold (lambda (field value errors)
              (validate-value (cdr field) value errors))
            '()
            spec
            (vector->list term))))))

;;; --- rendering: the term as a display string -----------------------------------

(define (render-value ftype value)
  (cond
   ((base-predicate ftype) value)
   ((resolve-type ftype) (render-term ftype value))
   (else "?")))

(define (render-term name term)
  (let ((spec (resolve-type name)))
    (if (and spec (vector? term))
        (string-join
         (map (lambda (field value) (render-value (cdr field) value))
              spec
              (vector->list term))
         " ")
        (error "cannot render invalid term" name))))
