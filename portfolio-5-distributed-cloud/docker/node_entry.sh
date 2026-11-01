#!/bin/bash
# Runs as root inside each container before PostgreSQL starts.
#  1. puts the TLS files where the postgres user may read them (the key must be private)
#  2. on the replica: waits until the primary accepts a REPLICATION login, then copies it with pg_basebackup
#  3. hands over to the normal PostgreSQL image entrypoint, on this node's own port and on 127.0.0.1 only
set -e
install -d -o postgres -g postgres -m 700 /var/lib/postgresql/tls
install -o postgres -g postgres -m 600 /certs/server.key /var/lib/postgresql/tls/server.key
install -o postgres -g postgres -m 644 /certs/server.crt /var/lib/postgresql/tls/server.crt
install -o postgres -g postgres -m 644 /certs/ca.crt     /var/lib/postgresql/tls/ca.crt
install -d -o postgres -g postgres /archive /backup

if [ "${P5_ROLE:-}" = "replica" ] && [ ! -s "$PGDATA/PG_VERSION" ]; then
  echo "replica: waiting for the primary to accept a replication login..."
  ready=no
  for i in $(seq 1 120); do
    if OUT="$(PGPASSWORD="$REPL_PW" psql "host=127.0.0.1 port=$PRIMARY_PORT user=replicator sslmode=require replication=true connect_timeout=3" -At -c "IDENTIFY_SYSTEM" 2>&1)"; then ready=yes; break; fi
    [ $((i % 10)) -eq 1 ] && echo "replica: still waiting (try $i): $(echo "$OUT" | head -1)"
    sleep 1
  done
  [ "$ready" = yes ] || { echo "replica: the primary never accepted the replication login. Last answer: $OUT"; exit 1; }
  install -d -o postgres -g postgres -m 700 "$PGDATA"
  echo "replica: copying the primary with pg_basebackup..."
  gosu postgres pg_basebackup \
     -d "host=127.0.0.1 port=$PRIMARY_PORT user=replicator password=$REPL_PW application_name=replica1 sslmode=require" \
     -D "$PGDATA" -R -X stream -C -S replica1 -c fast
  echo "replica: copy finished, starting PostgreSQL as a standby"
fi
exec docker-entrypoint.sh "$@" -c port="$PGPORT" -c listen_addresses=127.0.0.1
