#!/usr/bin/env bash
# =====================================================================
# Unity Public Library Network (UPLN) | MIT 8103 | Portfolio 4
# File    : Akosa_Antonella_301929153_P4_lib.sh   (sourced by the other .sh scripts; not run on its own)
# Purpose : Runs mongosh and psql the same way everywhere.
# =====================================================================
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
MONGO_CONTAINER="upln_mongo"
COMPOSE_FILE="$HERE/Akosa_Antonella_301929153_P4_docker-compose.mongo.yml"

# Run a JavaScript file from this folder in mongosh against the upln_nosql database.
mongorun() {
  if [ -n "${UPLN_MONGO_LOCAL:-}" ]; then          # test hook: a MongoDB-compatible server outside Docker
    (cd "$HERE" && "${MONGOSH_BIN:-mongosh}" --quiet "$UPLN_MONGO_LOCAL" --file "$1")
  else
    docker exec -w /p4 "$MONGO_CONTAINER" mongosh --quiet upln_nosql --file "$1"
  fi
}

# Run a small piece of JavaScript given as text.
mongoeval() {
  if [ -n "${UPLN_MONGO_LOCAL:-}" ]; then
    "${MONGOSH_BIN:-mongosh}" --quiet "$UPLN_MONGO_LOCAL" --eval "$1"
  else
    docker exec "$MONGO_CONTAINER" mongosh --quiet upln_nosql --eval "$1"
  fi
}

# Run SQL (from stdin) in the PostgreSQL database `upln` (read-only use in this portfolio).
psql_upln() {
  if [ -n "${UPLN_PSQL_LOCAL:-}" ]; then
    psql -X -q -h /tmp -p "$UPLN_PSQL_LOCAL" -U postgres -d upln -At -v ON_ERROR_STOP=1 "$@"
  else
    (cd "$ROOT" && docker compose -f Akosa_Antonella_301929153_docker-compose.yml exec -T postgres psql -X -q -U library_admin -d upln -At -v ON_ERROR_STOP=1 "$@")
  fi
}
