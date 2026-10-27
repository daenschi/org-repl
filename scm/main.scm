;;; logseq-repl — entry point. Run from the repo root:
;;;   GUILE_LOAD_PATH=scm guile-3.0 -s scm/main.scm
(use-modules (term server))

(primitive-load "types/bootstrap.scm")   ; seed vocabulary, dependency order
(start-server (string->number (or (getenv "PORT") "3000")))
