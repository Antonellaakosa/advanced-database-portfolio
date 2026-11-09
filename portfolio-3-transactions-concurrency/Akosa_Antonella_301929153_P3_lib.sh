#!/usr/bin/env bash
# =====================================================================
# Unity Public Library Network (UPLN) | MIT 8103 | Portfolio 3
# File    : Akosa_Antonella_301929153_P3_lib.sh   (sourced by the other scripts; not run on its own)
# Purpose : Runs psql the same way everywhere, and lets two or three
#           database sessions run AT THE SAME TIME with a time-stamped
#           timeline, so concurrency can be seen rather than imagined.
# =====================================================================
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
DB="${P3_DB:-upln_tx}"
STAFF_ID=2                       # a librarian of branch 1 from the Portfolio 1 sample data

# One psql call. SQL comes from stdin. Extra arguments are passed to psql.
psqlx() {
  if [ -n "${UPLN_PSQL_LOCAL:-}" ]; then          # test hook: a server outside Docker
    psql -X -q -h /tmp -p "$UPLN_PSQL_LOCAL" -U postgres -d "${P3_CONN_DB:-$DB}" -At -v VERBOSITY=terse "$@"
  else
    (cd "$ROOT" && docker compose -f Akosa_Antonella_301929153_docker-compose.yml exec -T postgres psql -X -q -U library_admin -d "${P3_CONN_DB:-$DB}" -At -v VERBOSITY=terse "$@")
  fi
}

# Run an SQL snippet quietly (used for fixtures and checks).
sql() { printf '%s\n' "$1" | psqlx -v ON_ERROR_STOP=1; }

TMPD="$(mktemp -d)"; trap 'rm -rf "$TMPD"' EXIT
PASS=0; FAIL=0

# Run one session in the background. Every output line gets a time stamp
# (milliseconds since the scenario started) so the sessions can be merged.
#   session LABEL DELAY_SECONDS "SQL TEXT"
session() {
  local label="$1" delay="$2" script="$3" file="$TMPD/$1.$RANDOM.log"
  ( sleep "$delay"
    printf '%s\n' "$script" | psqlx -v ON_ERROR_STOP=0 2>&1 | while IFS= read -r line; do
      printf '%06d|%s|%s\n' "$(( $(date +%s%3N) - T0 ))" "$label" "$line"
    done > "$file"
  ) &
  PIDS="$PIDS $!"
  LOGS="$LOGS $file"
}

# Start a scenario: resets the clock and the list of sessions.
begin_scenario() { T0=$(date +%s%3N); PIDS=""; LOGS=""; }

# Wait for every session, then print one merged timeline.
timeline() {
  wait $PIDS
  echo "      time  who  what happened"
  echo "    ------  ---  --------------------------------------------------------------"
  cat $LOGS 2>/dev/null | sort -t'|' -k1,1n | awk -F'|' '{ printf "   %5.1fs  %-3s  %s\n", $1/1000, $2, substr($0, index($0,$3)) }'
  echo
  CAPTURED="$(cat $LOGS 2>/dev/null)"
}

# Print the PASS/FAIL line returned by p3_check() and keep a tally.
check() {
  local line; line="$(sql "$1")"
  echo "   $line"
  case "$line" in PASS*) PASS=$((PASS+1));; *) FAIL=$((FAIL+1));; esac
}

# A banner for each part of a scenario.
hdr() { echo; echo "################################################################"; echo "# $1"; echo "################################################################"; }

# How many captured lines contain this text?
count_of() { printf '%s' "$CAPTURED" | grep -c -- "$1"; }

# Does the captured timeline contain this text?  (returns SQL boolean text)
saw() { if printf '%s' "$CAPTURED" | grep -q -- "$1"; then echo true; else echo false; fi; }

summary() {
  echo
  echo "=== $1: $PASS PASS, $FAIL FAIL ==="
  [ "$FAIL" -eq 0 ]
}

# A third session that looks at who is waiting for whom (the "observer").
observer_sql() {
cat <<'SQL'
SELECT 'OBSERVER: pid ' || a.pid || ' is WAITING (' || a.wait_event_type || ') and is blocked by pid ' ||
       array_to_string(pg_blocking_pids(a.pid), ',') || '  <- ' || left(regexp_replace(a.query, '\s+', ' ', 'g'), 60)
FROM pg_stat_activity a
WHERE a.datname = current_database() AND a.wait_event_type = 'Lock' AND a.pid <> pg_backend_pid();
SQL
}

# Print a small result table (with headers) from one query.
show_table() { printf '%s\n' "$1" | psqlx -P format=aligned -P tuples_only=off -P footer=off | sed 's/^/   /'; }
