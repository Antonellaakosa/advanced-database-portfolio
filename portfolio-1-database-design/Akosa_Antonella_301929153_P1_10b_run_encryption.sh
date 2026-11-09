#!/usr/bin/env bash
# =====================================================================
# Unity Public Library Network (UPLN) | MIT 8103 | Portfolio 1 (security)
# File    : 10b_run_encryption.sh
# Purpose : Runs 10_encryption.sql with a RANDOM key created just now.
#           The key exists only in this shell session: it is never saved
#           or committed. (In real life it would live in a secrets manager.)
# Run     : bash portfolio-1-database-design/10b_run_encryption.sh   (from the repo root)
# =====================================================================
set -u
KEY="$(openssl rand -base64 24)"
HERE="$(cd "$(dirname "$0")" && pwd)"
if [ -n "${UPLN_PSQL_LOCAL:-}" ]; then      # test hook: a server outside Docker
  psql -X -h /tmp -p "$UPLN_PSQL_LOCAL" -U postgres -d upln -v nin_key="$KEY" -v ON_ERROR_STOP=1 -q -f "$HERE/10_encryption.sql"
else
  docker compose exec -T postgres psql -X -U library_admin -d upln -v nin_key="$KEY" -v ON_ERROR_STOP=1 -q < "$HERE/10_encryption.sql"
fi
