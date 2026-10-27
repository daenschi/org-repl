# org-repl — Guile evaluator sidecar. Stdlib only.
FROM debian:bookworm-slim

RUN apt-get update \
 && apt-get install -y --no-install-recommends guile-3.0 \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY scm scm
COPY types types
COPY verify.scm verify.scm

ENV GUILE_LOAD_PATH=/app/scm
EXPOSE 3000
CMD ["guile-3.0", "-s", "scm/main.scm"]
