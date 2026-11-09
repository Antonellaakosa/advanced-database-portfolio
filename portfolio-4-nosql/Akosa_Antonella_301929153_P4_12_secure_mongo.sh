#!/usr/bin/env bash
# =====================================================================
# Unity Public Library Network (UPLN) | MIT 8103 | Portfolio 4
# File    : Akosa_Antonella_301929153_P4_12_secure_mongo.sh
# Purpose : Starts a password-protected MongoDB (second container, port 27018)
#           and PROVES the protection by trying to get past it:
#           anonymous access, a wrong password, a read-only account that tries
#           to write, an application account that reaches for other databases
#           or tries to create users.
# Run     : bash portfolio-4-nosql/Akosa_Antonella_301929153_P4_12_secure_mongo.sh
# =====================================================================
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENVF="$HERE/.env.mongo"
C=upln_mongo_secure
PASS=0; FAIL=0
check() { if [ "$3" = true ]; then echo "   PASS  $1  $2"; PASS=$((PASS+1)); else echo "   FAIL  $1  $2"; FAIL=$((FAIL+1)); fi; }
yes_if() { if eval "$1"; then echo true; else echo false; fi; }

echo "== Hardened MongoDB: authentication and least privilege =="
if [ ! -s "$ENVF" ]; then
  pw() { openssl rand -base64 18 | tr -d '/+=\n' | cut -c1-20; }
  { echo "MONGO_INITDB_ROOT_USERNAME=admin"; echo "MONGO_INITDB_ROOT_PASSWORD=$(pw)"; echo "APP_PW=$(pw)"; echo "REPORT_PW=$(pw)"; } > "$ENVF"
  chmod 600 "$ENVF"; echo "   random passwords created in .env.mongo (not committed)"
fi
set -a; . "$ENVF"; set +a
ROOT_PW="$MONGO_INITDB_ROOT_PASSWORD"

echo "   starting the secure container..."
docker compose -f "$HERE/Akosa_Antonella_301929153_P4_docker-compose.mongo-secure.yml" up -d >/dev/null 2>&1 || { echo "could not start the container"; exit 1; }
ok=false
for i in $(seq 1 90); do
  if docker exec "$C" mongosh --quiet -u admin -p "$ROOT_PW" --authenticationDatabase admin --eval 'db.runCommand({ping:1}).ok' 2>/dev/null | grep -q 1 \
     && docker exec "$C" mongosh --quiet -u catalogue_app -p "$APP_PW" --authenticationDatabase upln_nosql upln_nosql --eval 'db.runCommand({ping:1}).ok' 2>/dev/null | grep -q 1; then ok=true; break; fi
  sleep 2
done
$ok || { echo "the secure MongoDB did not become ready"; exit 1; }

as_app()    { docker exec "$C" mongosh --quiet -u catalogue_app    -p "$APP_PW"    --authenticationDatabase upln_nosql upln_nosql --eval "$1" 2>&1; }
as_report() { docker exec "$C" mongosh --quiet -u catalogue_report -p "$REPORT_PW" --authenticationDatabase upln_nosql upln_nosql --eval "$1" 2>&1; }
anon()      { docker exec "$C" mongosh --quiet upln_nosql --eval "$1" 2>&1; }

echo
echo "-- 1. Who may come in?"
A="$(anon 'db.titles.find().toArray().length')"
echo "   anonymous find: $(echo "$A" | head -1 | cut -c1-100)"
check S1 "an anonymous connection cannot read anything" "$(yes_if 'echo "$A" | grep -qi "requires authentication\|Unauthorized"')"
W="$(docker exec "$C" mongosh --quiet -u catalogue_app -p wrong-password --authenticationDatabase upln_nosql upln_nosql --eval 'db.titles.countDocuments({})' 2>&1)"
echo "   wrong password: $(echo "$W" | head -1 | cut -c1-100)"
check S2 "a wrong password is refused" "$(yes_if 'echo "$W" | grep -qi "Authentication failed"')"

echo
echo "-- 2. What may each account do?"
as_app 'load("/p4/data/Akosa_Antonella_301929153_P4_migrated_titles.js"); db.titles.deleteMany({}); db.titles.insertMany(migratedTitles).insertedIds.length' >/dev/null
N="$(as_app 'db.titles.countDocuments({})' | tail -1)"
echo "   application account loaded the catalogue and counts: $N titles"
check S3 "the application account can write and read its own database (10 titles)" "$(yes_if '[ "$N" = 10 ]')"
R="$(as_report 'db.titles.countDocuments({})' | tail -1)"
check S4 "the reporting account can read the same data" "$(yes_if '[ "$R" = 10 ]')"
RW="$(as_report 'db.titles.insertOne({title:"should not work"})')"
echo "   reporting account trying to insert: $(echo "$RW" | head -1 | cut -c1-100)"
check S5 "the reporting account cannot write" "$(yes_if 'echo "$RW" | grep -qi "not authorized"')"
OD="$(docker exec "$C" mongosh --quiet -u catalogue_app -p "$APP_PW" --authenticationDatabase upln_nosql --eval 'db.getSiblingDB("admin").system.users.find().toArray()' 2>&1)"
echo "   application account reading the admin database: $(echo "$OD" | head -1 | cut -c1-100)"
check S6 "the application account cannot read the admin database (where accounts are stored)" "$(yes_if 'echo "$OD" | grep -qi "not authorized"')"
CU="$(as_app 'db.createUser({user:"intruder", pwd:"x", roles:["root"]})')"
echo "   application account trying to create an administrator: $(echo "$CU" | head -1 | cut -c1-100)"
check S7 "the application account cannot create users or grant itself more rights" "$(yes_if 'echo "$CU" | grep -qi "not authorized"')"

echo
echo "-- 3. Exposure and secrets"
PUB="$(grep -c '127.0.0.1:27018' "$HERE/Akosa_Antonella_301929153_P4_docker-compose.mongo-secure.yml")"
check S8 "the secure port is published to this machine only (127.0.0.1)" "$(yes_if '[ "$PUB" = 1 ]')"
check S9 ".env.mongo (passwords) is excluded from GitHub by .gitignore" "$(yes_if 'grep -q "^.env.mongo" "$HERE/.gitignore"')"
check S10 "the password file is private to its owner (mode 600)" "$(yes_if '[ "$(stat -c %a "$ENVF")" = 600 ]')"

echo
echo "== Secure MongoDB: $PASS PASS, $FAIL FAIL =="
echo "Not covered here: TLS for MongoDB connections (shown for PostgreSQL in Portfolio 5) and encryption at rest."
[ "$FAIL" -eq 0 ]
