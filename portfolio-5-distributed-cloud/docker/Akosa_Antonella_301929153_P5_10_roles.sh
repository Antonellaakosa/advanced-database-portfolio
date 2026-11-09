#!/bin/bash
# Runs once, when a primary or shard database is first created (Docker initdb hook).
set -e
if [ "${P5_ROLE}" = "primary" ]; then SET=primary; DB=upln; else SET=shard; DB=shard; fi
psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$DB" \
  -v role_set="$SET" -v repl_pw="${REPL_PW:-}" -v app_pw="${APP_PW:-}" -v report_pw="${REPORT_PW:-}" -v fdw_pw="${FDW_PW:-}" \
  -f /sql/10_roles.sql
