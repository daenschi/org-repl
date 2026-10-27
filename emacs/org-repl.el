;;; org-repl.el — org-mode as the graph editor. Forced structure at
;;; creation, validation on save, one registry (the Guile sidecar).
;;;
;;; Conventions (all plain org, no new syntax):
;;;   Type definition heading: :TYPE: type
;;;     :FIELDS: doors:wholenumbers windows:wholenumbers address:streetname
;;;   Term heading:            :TYPE: house
;;;     :TERM: ["2", "5", ["Bahnhof", "12"]]
;;;   Command heading:         :CMD: build-house
;;;     :RUN: echo "2 5 Bahnhof 12"
;;;     :EXPECT: 2 5 Bahnhof 12
;;;     :DEPS: streetname         ; optional, run order = dependency order
;;;
;;; Dependencies go one direction only: a field's type must be defined
;;; before it is used (the sidecar refuses forward and self references).

(require 'org)
(require 'json)
(require 'url)

(defgroup org-repl nil
  "Org graphs validated by the Guile sidecar."
  :group 'tools)

(defcustom org-repl-sidecar-url "http://localhost:3000"
  "Base URL of the Guile sidecar (compose service `repl')."
  :type 'string
  :group 'org-repl)

;;; --- the forced skeletons -----------------------------------------------------

(defun org-repl-capture-type (name fields)
  "Insert a type definition. NAME like streetname, FIELDS like
\"word:characters number:wholenumbers\" — every referenced type must
already exist (that is the one-direction rule)."
  (interactive "sType name: \nsFields (name:type, space separated): ")
  (org-insert-heading)
  (insert name)
  (org-set-property "TYPE" "type")
  (org-set-property "FIELDS" fields))

(defun org-repl-capture-term (type)
  "Insert a term of TYPE with an empty :TERM: array to fill in."
  (interactive "sTerm of type: ")
  (org-insert-heading)
  (insert "term in " type)
  (org-set-property "TYPE" type)
  (org-set-property "TERM" "[]"))

(defun org-repl-capture-command (name run expect)
  "Insert a command block: RUN is a shell command, EXPECT its stdout."
  (interactive "sCommand name: \nsShell command: \nsExpected stdout: ")
  (org-insert-heading)
  (insert name)
  (org-set-property "CMD" name)
  (org-set-property "RUN" run)
  (org-set-property "EXPECT" expect))

;;; --- sidecar I/O ----------------------------------------------------------------

(defun org-repl--post (path object)
  "POST OBJECT as JSON to the sidecar; return the parsed answer."
  (let* ((url-request-method "POST")
         (url-request-extra-headers '(("Content-Type" . "application/json")))
         (url-request-data (json-encode object))
         (buffer (url-retrieve-synchronously
                  (concat org-repl-sidecar-url path) 'silent 'inhibit-cookies)))
    (when buffer
      (with-current-buffer buffer
        (goto-char (point-min))
        (if (search-forward "\n\n" nil t)
            (json-read-from-string (buffer-substring (point) (point-max)))
          (error "no JSON in response")))))

;;; --- validation on save ----------------------------------------------------------

(defun org-repl--entries (property)
  "Yield (position . alist) for every heading carrying PROPERTY."
  (let ((entries '()))
    (org-map-entries
     (lambda ()
       (let ((data (org-entry-properties)))
         (when (assoc property data)
           (push data entries))))
     nil 'file)
    (nreverse entries)))

(defun org-repl--fields->json (fields)
  "Parse \"a:t b:t\" into a vector of field objects for /define-type."
  (mapcar (lambda (f)
            (let ((parts (split-string f ":")))
              (list (cons "name" (car parts))
                    (cons "type" (cadr parts)))))
          (split-string fields)))

(defun org-repl-validate-buffer ()
  "Validate every entry in the current buffer against the sidecar.
Type definitions go to /define-type (forward and self references are
refused there), terms to /eval. Verdicts land as messages."
  (interactive)
  (save-excursion
    ;; type definitions first — journal order is the dependency order
    (dolist (entry (org-repl--entries "FIELDS"))
      (let ((name (cdr (assoc "TYPE" entry)))
            (fields (cdr (assoc "FIELDS" entry))))
        (when (and name (not (equal name "type")))
          (condition-case err
              (let ((answer (org-repl--post "/define-type"
                                            (list (cons "name" name)
                                                  (cons "fields" (org-repl--fields->json fields))))))
                (message "%s: %s" name (alist-get 'status answer)))
            (error
             (message "%s: refused — %s" name (error-message-string err)))))))
    ;; then terms
    (dolist (entry (org-repl--entries "TERM"))
      (let ((type (cdr (assoc "TYPE" entry)))
            (term (cdr (assoc "TERM" entry))))
        (condition-case err
            (let* ((answer (org-repl--post "/eval"
                                           (list (cons "type" type)
                                                 (cons "term" (json-read-from-string term)))))
                   (status (alist-get 'status answer)))
              (message "%s: %s %s" type status
                       (or (alist-get 'rendered answer)
                           (alist-get 'errors answer) "")))
          (error
           (message "%s: sidecar error — %s" type (error-message-string err)))))))

(defun org-repl-before-save ()
  "Hook: validate terms on save. Does not block saving — it reports."
  (when (derived-mode-p 'org-mode)
    (org-repl-validate-buffer)))

;;;###autoload
(define-minor-mode org-repl-mode
  "Org headings as typed terms, validated against the Guile sidecar."
  :lighter " org-repl"
  (if org-repl-mode
      (add-hook 'before-save-hook #'org-repl-before-save nil t)
    (remove-hook 'before-save-hook #'org-repl-before-save t)))

(provide 'org-repl)
;;; org-repl.el ends here
