;;; types/bootstrap.scm — the seed vocabulary, in dependency order.
;;; The three primitives (characters, wholenumbers, symbols) are built into
;;; term/types.scm. These are the first composite types — each one only
;;; references types defined ABOVE it (one-direction rule).
(use-modules (term types) (term dictionary))

;;; the shared dictionary: one file, all entries, referenced everywhere
(load-dictionary! "types/dictionary.tsv")

;; streetname = word(a dictionary entry) + number
(define-type! "streetname"
  '(("word" . "german")
    ("number" . "wholenumbers")))

;; house = doors + windows + address(a streetname, defined above)
(define-type! "house"
  '(("doors" . "wholenumbers")
    ("windows" . "wholenumbers")
    ("address" . "streetname")))
