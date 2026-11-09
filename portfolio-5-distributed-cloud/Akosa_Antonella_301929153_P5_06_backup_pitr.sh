#!/usr/bin/env bash
# =====================================================================
# UPLN | MIT 8103 | Portfolio 5
# File    : Akosa_Antonella_301929153_P5_06_backup_pitr.sh
# Purpose : Backup and point-in-time recovery (PITR) drill.
#           1. take a physical base backup of the primary and verify it
#           2. keep writing; the primary archives its WAL (the change log)
#           3. mark a point in time, then simulate an accident (all ledger rows deleted)
#           4. build a SEPARATE restored server from the base backup + archived WAL,
#              stopping at the marked time, and measure how long that takes (RTO)
#           5. prove the lost rows are back and nothing after the mark leaked in (RPO)
#           The live primary is never touched by the restore.
# Run     : bash portfolio-5-distributed-cloud/Akosa_Antonella_301929153_P5_06_backup_pitr.sh
# =====================================================================
set -u
source "$(dirname "$0")/Akosa_Antonella_301929153_P5_lib.sh"
begin_scenario "06_backup_pitr"
echo "== Backup and point-in-time recovery drill =="

RARGS="-c config_file=/etc/p5/Akosa_Antonella_301929153_P5_postgresql.p5.conf -c hba_file=/etc/p5/Akosa_Antonella_301929153_P5_pg_hba.p5.conf -c ssl_cert_file=/var/lib/postgresql/tls/server.crt -c ssl_key_file=/var/lib/postgresql/tls/server.key -c ssl_ca_file=/var/lib/postgresql/tls/ca.crt -c archive_mode=off -c port=5545 -c listen_addresses=127.0.0.1"

# ---------- helpers that differ between Docker and the local test hook ----------
take_base_backup() {
  if [ -n "$LOCAL" ]; then
    rm -rf "$LROOT/backup/base"
    su postgres -c "PGSSLMODE=require PGPASSWORD='$REPL_PW' $PGBIN/pg_basebackup -h 127.0.0.1 -p 5541 -U replicator -D $LROOT/backup/base -Fp -X stream -c fast --manifest-checksums=sha256" 2>&1
  else
    docker exec -u postgres -e PGSSLMODE=require -e PGPASSWORD="$REPL_PW" upln_p5_primary bash -c "rm -rf /backup/base && pg_basebackup -h 127.0.0.1 -p 5541 -U replicator -D /backup/base -Fp -X stream -c fast --manifest-checksums=sha256" 2>&1
  fi
}
verify_backup() {
  if [ -n "$LOCAL" ]; then su postgres -c "$PGBIN/pg_verifybackup $LROOT/backup/base" 2>&1
  else docker exec -u postgres upln_p5_primary pg_verifybackup /backup/base 2>&1; fi
}
archive_count() { ls_archive | grep -vc '\.backup$' ; }
ls_archive() { if [ -n "$LOCAL" ]; then ls "$LROOT/archive"; else docker exec upln_p5_primary ls /archive; fi; }
start_restore() {   # $1 = target time
  local T="$1"
  if [ -n "$LOCAL" ]; then
    su postgres -c "$PGBIN/pg_ctl -D $LROOT/restore -m immediate stop" >/dev/null 2>&1
    rm -rf "$LROOT/restore"; cp -a "$LROOT/backup/base" "$LROOT/restore"; chown -R postgres "$LROOT/restore"; chmod 700 "$LROOT/restore"
    touch "$LROOT/restore/recovery.signal"
    { echo "restore_command = 'cp $LROOT/archive/%f %p'"; echo "recovery_target_time = '$T'"; echo "recovery_target_action = 'promote'"; } >> "$LROOT/restore/postgresql.auto.conf"
    su postgres -c "$PGBIN/pg_ctl -D $LROOT/restore -w -l $LROOT/restore.log -o \"$(local_args restore) -c archive_mode=off -p 5545 -k $LROOT/sock\" start" >/dev/null 2>&1
  else
    docker rm -f upln_p5_restore >/dev/null 2>&1
    docker run -d --name upln_p5_restore --network host --entrypoint bash \
      -v upln_p5_p5_backup:/backup:ro -v upln_p5_p5_archive:/archive:ro -v "$HERE/conf:/etc/p5:ro" -v "$HERE/certs:/certs:ro" \
      postgres:16 -c "
        install -d -o postgres -g postgres -m 700 /var/lib/postgresql/tls
        install -o postgres -g postgres -m 600 /certs/server.key /var/lib/postgresql/tls/server.key
        install -o postgres -g postgres -m 644 /certs/server.crt /certs/ca.crt /var/lib/postgresql/tls/
        cp -a /backup/base /var/lib/postgresql/restore && chown -R postgres:postgres /var/lib/postgresql/restore && chmod 700 /var/lib/postgresql/restore
        touch /var/lib/postgresql/restore/recovery.signal
        printf \"restore_command = 'cp /archive/%%f %%p'\nrecovery_target_time = '$T'\nrecovery_target_action = 'promote'\n\" >> /var/lib/postgresql/restore/postgresql.auto.conf
        exec gosu postgres postgres -D /var/lib/postgresql/restore $RARGS" >/dev/null
  fi
}
stop_restore() {
  if [ -n "$LOCAL" ]; then su postgres -c "$PGBIN/pg_ctl -D $LROOT/restore -m immediate stop" >/dev/null 2>&1; rm -rf "$LROOT/restore" "$LROOT/backup/base"
  else docker rm -f upln_p5_restore >/dev/null 2>&1; docker exec -u postgres upln_p5_primary rm -rf /backup/base >/dev/null 2>&1; fi
}

# ---------- 1. base backup ----------
hdr "1. Physical base backup of the primary"
# clear anything a previous run of this drill left behind, so the drill can be repeated and the counts stay exact
asql primary "delete from p5_ledger where note like 'before-backup-%' or note like 'after-backup-%' or note like 'after-target-%'" > /dev/null
asql primary "insert into p5_ledger(note) select 'before-backup-' || g from generate_series(1,1000) g" > /dev/null
OUT="$(take_base_backup)"; BR=$?
V="$(verify_backup)"
echo "   $(echo "$V" | tail -1)"
check B1 "base backup taken and every file verified against its checksum manifest" "$(yes_if 'echo "$V" | grep -qi "verified"')"

# ---------- 2. keep working, then mark a time ----------
hdr "2. Business carries on after the backup (this is what only the WAL archive remembers)"
asql primary "insert into p5_ledger(note) select 'after-backup-' || g from generate_series(1,500) g" > /dev/null
sleep 1
TARGET="$(asql primary "select now()::text")"
GOOD="$(asql primary "select count(*) from p5_ledger")"
echo "   rows at the chosen recovery point: $GOOD    recovery point: $TARGET"
sleep 2

# ---------- 3. accident ----------
hdr "3. The accident"
asql primary "insert into p5_ledger(note) select 'after-target-' || g from generate_series(1,10) g" > /dev/null
asql primary "delete from p5_ledger" > /dev/null
LEFT="$(asql primary "select count(*) from p5_ledger")"
echo "   someone ran DELETE without WHERE: $LEFT rows left (was $GOOD)"
check B2 "the accident is real: the live ledger is empty" "$(yes_if '[ "$LEFT" = 0 ]')"
BEFORE_ARCH="$(asql primary "select archived_count from pg_stat_archiver")"
asql primary "select pg_switch_wal()" > /dev/null
for i in $(seq 1 60); do [ "$(asql primary "select archived_count from pg_stat_archiver")" -gt "$BEFORE_ARCH" ] && break; sleep 1; done
FAILS="$(asql primary "select failed_count from pg_stat_archiver")"
check B3 "WAL archiving is working (archived files: $(archive_count), failed attempts: $FAILS)" "$(yes_if '[ "$FAILS" = 0 ] && [ "$(archive_count)" -ge 1 ]')"

# ---------- 4. restore ----------
hdr "4. Restore into a separate server, stopping at the recovery point"
T0="$(now_ms)"
start_restore "$TARGET"
ok=false
for i in $(seq 1 120); do
  if [ "$(np restore library_admin "" -c "select pg_is_in_recovery()" 2>/dev/null)" = f ]; then ok=true; break; fi
  sleep 1
done
RTO=$(( $(now_ms) - T0 ))
echo "   restored server accepted queries after $((RTO/1000)).$(printf %03d $((RTO%1000))) s   (recovery time, RTO for this small database)"
check B4 "the restored server finished recovery and is open for queries" "$ok"
RC="$(np restore library_admin "" -c "select count(*) from p5_ledger" 2>&1 || true)"
RA="$(np restore library_admin "" -c "select count(*) from p5_ledger where note like 'after-target-%'" 2>&1 || true)"
RB="$(np restore library_admin "" -c "select count(*) from p5_ledger where note like 'after-backup-%'" 2>&1 || true)"
echo "   restored server: $RC rows in total, $RB written after the backup, $RA written after the recovery point"
check B5 "all $GOOD rows are back (the DELETE is undone)" "$(yes_if '[ "$RC" = "$GOOD" ]')"
check B6 "the 500 rows written AFTER the base backup came back from the WAL archive (true point-in-time recovery)" "$(yes_if '[ "$RB" = 500 ]')"
check B7 "nothing after the recovery point leaked in (0 'after-target' rows)" "$(yes_if '[ "$RA" = 0 ]')"
check B8 "the live primary was not touched by the restore (still empty, still running)" "$(yes_if '[ "$(asql primary "select count(*) from p5_ledger")" = 0 ]')"
echo "   the recovery point lost no committed work (RPO = 0 rows for everything before $TARGET)"

# put the live data back from the restored copy so later scripts have rows, then clean up
np restore library_admin "" -c "copy (select note, created_at from p5_ledger order by id) to stdout" | admin primary -c "copy p5_ledger(note, created_at) from stdin" > /dev/null
stop_restore
check B9 "the live ledger was repopulated from the restored copy ($(asql primary "select count(*) from p5_ledger") rows) and the scratch server removed" "$(yes_if '[ "$(asql primary "select count(*) from p5_ledger")" = "$GOOD" ]')"
summary
