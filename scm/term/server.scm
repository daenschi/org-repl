;;; term/server.scm — the HTTP shell. The core (term types) stays pure;
;;; this file owns the I/O: sockets, the JSON, the registry mutations.

(define-module (term server)
  #:use-module (web server)
  #:use-module (web request)
  #:use-module (web response)
  #:use-module (web uri)
  #:use-module (ice-9 textual-ports)
  #:use-module (rnrs bytevectors)
  #:use-module (term json)
  #:use-module (term types)
  #:export (start-server))

;;; Every response is JSON, utf-8, never cached (the Logseq plugin must
;;; always see the current registry).
(define (respond x)
  (values (build-response
           #:code 200
           #:headers '((content-type . (application/json (charset . "utf-8")))
                       (cache-control . (no-store))))
          (json-write-string x)))

(define (respond-error msg)
  (respond (list (cons "status" "error") (cons "error" msg))))

;;; fields arrive as JSON #((("name" . "word") ("type" . "characters")) ...)
;;; and become ((word . characters) ...) for define-type!.
(define (json-fields v)
  (map (lambda (f) (cons (assoc-ref f "name") (assoc-ref f "type")))
       (vector->list v)))

(define (route-types)
  (respond
   (list->vector
    (map (lambda (entry)
           (list (cons "name" (car entry))
                 (cons "fields"
                       (list->vector
                        (map (lambda (f)
                               (list (cons "name" (car f))
                                     (cons "type" (cdr f))))
                             (cdr entry))))))
         (all-types)))))

(define (route-define-type body)
  (catch #t
    (lambda ()
      (let* ((data   (json-read-string body))
             (name   (assoc-ref data "name"))
             (fields (assoc-ref data "fields")))
        (if (not (and (string? name) (vector? fields)))
            (respond-error "need: name (string) + fields (array)")
            (begin
              (define-type! name (json-fields fields))
              (respond (list (cons "status" "ok")
                             (cons "type" name)))))))
    (lambda (key . args)
      (respond-error (format #f "~a ~a" key args)))))

;;; validate + eval share one shape: {type, term} → verdict + rendered text
(define (check-term body eval?)
  (catch #t
    (lambda ()
      (let* ((data (json-read-string body))
             (name (assoc-ref data "type"))
             (term (assoc-ref data "term")))
        (if (not (and (string? name) (vector? term)))
            (respond-error "need: type (string) + term (array)")
            (let ((errors (validate-term name term)))
              (if (null? errors)
                  (respond (list (cons "status" "ok")
                                 (cons "rendered" (render-term name term))))
                  (respond (list (cons "status" "invalid")
                                 (cons "errors" (list->vector errors)))))))))
    (lambda (key . args)
      (respond-error (format #f "~a ~a" key args)))))

(define (handler request body)
  (catch #t
    (lambda ()
      (let ((path   (uri-path (request-uri request)))
            (body-s (if body (utf8->string body) "")))
        (cond
         ((equal? path "/types")       (route-types))
         ((equal? path "/define-type") (route-define-type body-s))
         ((equal? path "/validate")    (check-term body-s #f))
         ((equal? path "/eval")        (check-term body-s #t))
         ((equal? path "/health")      (respond '(("status" . "ok"))))
         (else (values (build-response #:code 404) "not found")))))
    (lambda (key . args)
      (values (build-response #:code 500)
              (format #f "server error: ~a ~a" key args)))))

(define (start-server port)
  (display "logseq-repl listening on :") (display port) (newline)
  (run-server handler 'http (list #:addr INADDR_ANY #:port port)))
