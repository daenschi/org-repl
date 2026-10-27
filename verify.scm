;;; verify.scm — acceptance checks. From the repo root:
;;;   GUILE_LOAD_PATH=scm guile-3.0 -s verify.scm
(use-modules (term types) (term dictionary))

(define fails 0)
(define (check name ok?)
  (display (if ok? (string-append "PASS  " name "\n")
                   (string-append "FAIL  " name "\n")))
  (or ok? (set! fails (+ fails 1))))

;;; --- the three primitives ------------------------------------------------------
(check "characters accepts letters"
       (null? (validate-value "characters" "asuihd" '())))
(check "characters rejects digits"
       (pair? (validate-value "characters" "abc1" '())))
(check "wholenumbers accepts a signed integer"
       (null? (validate-value "wholenumbers" "-2" '())))
(check "wholenumbers accepts a plus sign"
       (null? (validate-value "wholenumbers" "+3" '())))
(check "wholenumbers rejects a decimal"
       (pair? (validate-value "wholenumbers" "1.5" '())))
(check "symbols accepts symbol characters"
       (null? (validate-value "symbols" "¦@#§!" '())))
(check "symbols rejects letters"
       (pair? (validate-value "symbols" "a" '())))

;;; --- one-direction composition --------------------------------------------------
;; streetname = word + number (defined BEFORE house uses it)
(define-type! "streetname" '(("word" . "characters") ("number" . "wholenumbers")))
(check "streetname validates a good term"
       (null? (validate-term "streetname" #("Bahnhof" "12"))))
(check "streetname rejects a non-number second field"
       (pair? (validate-term "streetname" #("Bahnhof" "x"))))
(check "streetname rejects wrong arity"
       (pair? (validate-term "streetname" #("Bahnhof"))))
(check "streetname renders as text"
       (equal? "Bahnhof 12" (render-term "streetname" #("Bahnhof" "12"))))

;; forward reference is refused at definition time
(check "forward reference is refused"
       (catch #t
         (lambda ()
           (define-type! "tooearly" '(("x" . "notdefinedyet")) #f))
         (lambda (k . a) #t)))

;; self reference is refused at definition time
(check "self reference is refused"
       (catch #t
         (lambda ()
           (define-type! "house" '(("address" . "house")) #f))
         (lambda (k . a) #t)))

;;; --- dictionary references (shared source, no duplicates) ------------------------
(load-dictionary! "types/dictionary.tsv")
(check "german reference resolves an existing entry"
       (null? (validate-value "german" "Bahnhof" '())))
(check "german reference rejects a non-entry"
       (pair? (validate-value "german" "NoSuchWord" '())))
(check "english reference resolves an existing entry"
       (null? (validate-value "english" "station" '())))

;;; --- the house example from the user --------------------------------------------
(define-type! "house"
  '(("doors" . "wholenumbers")
    ("windows" . "wholenumbers")
    ("address" . "streetname")))
(check "house validates (2 5 Bahnhof 12)"
       (null? (validate-term "house" #("2" "5" #("Bahnhof" "12")))))
(check "house rejects a bad address"
       (pair? (validate-term "house" #("2" "5" #("Bahnhof" "x")))))
(check "house renders nested values"
       (equal? "2 5 Bahnhof 12"
               (render-term "house" #("2" "5" #("Bahnhof" "12")))))
(check "house rejects wrong arity"
       (pair? (validate-term "house" #("2" "5"))))
(check "unknown type is reported"
       (pair? (validate-term "nosuchtype" #("x"))))

(newline)
(display (if (= 0 fails) "ALL CHECKS PASSED\n"
             (string-append (number->string fails) " CHECK(S) FAILED\n")))
(exit (if (= 0 fails) 0 1))
