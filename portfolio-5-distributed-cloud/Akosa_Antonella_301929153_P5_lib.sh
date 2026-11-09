#!/usr/bin/env bash
# =====================================================================
# UPLN | MIT 8103 | Portfolio 5
# File    : lib.sh   (sourced by the other scripts; not run on its own)
# Purpose : One place that knows how to reach each node, start/stop it,
#           and print PASS/FAIL lines. Works with Docker (normal use).
#           UPLN_P5_LOCAL=1 is a test hook that runs the same nodes as
#           plain processes on one machine.
# =====================================================================
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
ENVF="$HERE/.env.p5"
RESULTS="$HERE/results/p5_results.tsv"
mkdir -p "$HERE/results"
[ -s "$ENVF" ] && set -a && . "$ENVF" && set +a

LOCAL="${UPLN_P5_LOCAL:-}"
LROOT="${UPLN_P5_LROOT:-/var/tmp/p5}"            # local test hook: where node folders live
PGBIN="${UPLN_P5_PGBIN:-/usr/lib/postgresql/16/bin}"

node_port() { case "$1" in primary) echo 5541;; replica) echo 5542;; shard_north) echo 5543;; shard_south) echo 5544;; restore) echo 5545;; esac; }
node_db()   { case "$1" in shard_*) echo shard;; *) echo upln;; esac; }
pw_of()     { case "$1" in library_admin) echo "${ADMIN_PW:-}";; replicator) echo "${REPL_PW:-}";; p5_app) echo "${APP_PW:-}";; p5_report) echo "${REPORT_PW:-}";; fdw_user) echo "${FDW_PW:-}";; *) echo "${3:-}";; esac; }
CAFILE() { [ -n "$LOCAL" ] && echo "$HERE/certs/ca.crt" || echo /certs/ca.crt; }

# address of a node as seen BY ANOTHER NODE (used for replication and foreign tables)
peer_host() { echo 127.0.0.1; }          # every node is on this machine's own network, each on its own port
peer_port() { node_port "$1"; }

dc() { docker compose -p upln_p5 -f "$HERE/docker-compose.p5.yml" --env-file "$ENVF" "$@"; }

# np NODE USER [DB]  [psql args...]   : run SQL (from stdin or -c) on a node, over TCP with TLS
#   env  PGSSLMODE (default require), PGPASSWORD_OVERRIDE (to test a wrong password)
np() {
  local node="$1" user="$2" db="${3:-}"; shift 3 || shift $#
  [ -z "$db" ] && db="$(node_db "$node")"
  local pw="${PGPASSWORD_OVERRIDE:-$(pw_of "$user")}" ssl="${PGSSLMODE:-require}"
  if [ -n "$LOCAL" ]; then
    PGOPTIONS="-c client_min_messages=warning" PGPASSWORD="$pw" PGSSLMODE="$ssl" PGSSLROOTCERT="$HERE/certs/ca.crt" psql -X -q -h 127.0.0.1 -p "$(node_port "$node")" -U "$user" -d "$db" -At -v ON_ERROR_STOP=1 "$@"
  else
    docker exec -i -e PGPASSWORD="$pw" -e PGSSLMODE="$ssl" -e PGSSLROOTCERT=/certs/ca.crt -e PGOPTIONS="-c client_min_messages=warning" "upln_p5_$node" psql -X -q -h 127.0.0.1 -p "$(node_port "$node")" -U "$user" -d "$db" -At -v ON_ERROR_STOP=1 "$@"
  fi
}
admin() { local n="$1"; shift; np "$n" library_admin "" "$@"; }       # admin SQL on a node
asql()  { local n="$1" q="$2"; np "$n" library_admin "" -c "$q"; }    # one query, one value back

# ---- start / stop -----------------------------------------------------
node_stop() {   # node [immediate]
  if [ -n "$LOCAL" ]; then
    local mode=fast; [ "${2:-}" = immediate ] && mode=immediate
    su postgres -c "$PGBIN/pg_ctl -D $LROOT/$1 -m $mode -w stop" >/dev/null 2>&1 || true
  else
    if [ "${2:-}" = immediate ]; then docker kill "upln_p5_$1" >/dev/null; else docker stop -t 20 "upln_p5_$1" >/dev/null; fi
  fi
}
node_start() {
  if [ -n "$LOCAL" ]; then
    local p; p="$(node_port "$1")"
    su postgres -c "$PGBIN/pg_ctl -D $LROOT/$1 -w -l $LROOT/$1.log -o \"$(local_args "$1") -p $p -k $LROOT/sock\" start" >/dev/null 2>&1
  else
    docker start "upln_p5_$1" >/dev/null
  fi
}
wait_node() {   # node [seconds]
  local n="$1" t="${2:-90}" i=0
  until np "$n" library_admin "" -c "select 1" >/dev/null 2>&1; do i=$((i+1)); [ "$i" -ge "$t" ] && { echo "node $n did not come up"; return 1; }; sleep 1; done
}
local_args() {
  echo "-c config_file=$HERE/conf/postgresql.p5.conf -c hba_file=$HERE/conf/pg_hba.p5.conf -c ssl_cert_file=$LROOT/tls/server.crt -c ssl_key_file=$LROOT/tls/server.key -c ssl_ca_file=$LROOT/tls/ca.crt -c listen_addresses=127.0.0.1 -c archive_command='test ! -f $LROOT/archive/%f && cp %p $LROOT/archive/%f'"
}

# ---- reporting --------------------------------------------------------
hdr()  { echo; echo "----- $1 -----"; }
begin_scenario() { S="$1"; grep -v "^$S	" "$RESULTS" 2>/dev/null > "$RESULTS.tmp" || true; mv -f "$RESULTS.tmp" "$RESULTS" 2>/dev/null || true; : >> "$RESULTS"; }
check() {       # code "label" condition(0/1 as true/false text)
  local code="$1" label="$2" ok="$3" word=FAIL
  [ "$ok" = "true" ] && word=PASS
  printf "   %s  %s  %s\n" "$word" "$code" "$label"
  printf "%s\t%s\t%s\t%s\n" "$S" "$code" "$word" "$label" >> "$RESULTS"
}
yes_if() { if eval "$1"; then echo true; else echo false; fi; }
summary() {
  local p f
  p="$(awk -F'\t' -v s="$S" '$1==s && $3=="PASS"' "$RESULTS" | wc -l)"
  f="$(awk -F'\t' -v s="$S" '$1==s && $3=="FAIL"' "$RESULTS" | wc -l)"
  echo; echo "=== $S: $p PASS, $f FAIL ==="
}
now_ms() { date +%s%3N; }
