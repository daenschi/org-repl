;;; term/dictionary.scm — the shared dictionary: entries, not copies.
;;;
;;; A dictionary is a TSV file of German<TAB>English lines (dict.cc format).
;;; Entries are the single source of truth: a term REFERENCES an entry by
;;; its German or English word — it never duplicates the entry's text.
;;; Validity of a dictionary reference = the entry EXISTS in the dictionary.

(define-module (term dictionary)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-13)
  #:use-module (ice-9 textual-ports)
  #:export (load-dictionary! dictionary-entry?))

(define *entries* '())   ; list of (german . english) pairs

;;; parse one TSV line into a (german . english) pair, or #f to skip it
(define (parse-line line)
  (if (or (string-prefix? "#" line)
          (not (string-contains line "\t")))
      #f
      (let ((parts (string-split line #\tab)))
        (cons (car parts) (string-join (cdr parts) " ")))))

;;; read a TSV dictionary file into *entries*
(define (load-dictionary! path)
  (when (file-exists? path)
    (set! *entries*
          (call-with-input-file path
            (lambda (port)
              (let loop ((acc '()))
                (let ((line (get-line port)))
                  (if (eof-object? line)
                      acc
                      (let ((entry (parse-line line)))
                        (loop (if entry (cons entry acc) acc)))))))))

;;; Does WORD exist as an entry in language LANG ("german" or "english")?
(define (dictionary-entry? lang word)
  (and (string? word)
       (any (lambda (e)
              (cond
               ((equal? lang "german")  (equal? (car e) word))
               ((equal? lang "english") (equal? (cdr e) word))
               (else #f)))
            *entries*)))
