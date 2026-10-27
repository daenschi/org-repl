# org-repl — headless Emacs as the org-mode enforcer.
FROM debian:bookworm-slim

RUN apt-get update \
 && apt-get install -y --no-install-recommends emacs-nox curl ca-certificates \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /opt
COPY emacs/org-repl.el /opt/org-repl.el

WORKDIR /notes
CMD ["/bin/bash"]
