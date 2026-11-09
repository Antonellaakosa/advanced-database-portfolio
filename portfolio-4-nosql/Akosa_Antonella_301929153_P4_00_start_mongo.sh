#!/usr/bin/env bash
# =====================================================================
# Unity Public Library Network (UPLN) | MIT 8103 | Portfolio 4
# File    : 00_start_mongo.sh
# Purpose : Starts MongoDB (a separate container, port 127.0.0.1:27017),
#           waits until it answers, and prints its version.
# Run     : bash portfolio-4-nosql/00_start_mongo.sh        (from the repo root)
# =====================================================================
set -u
source "$(dirname "$0")/lib.sh"
echo "== Starting MongoDB for Portfolio 4 =="
docker compose -f "$COMPOSE_FILE" up -d || { echo "Could not start MongoDB. Is Docker running?"; exit 1; }
echo -n "   waiting for MongoDB to answer"
for i in $(seq 1 40); do
  if docker exec "$MONGO_CONTAINER" mongosh --quiet --eval "db.adminCommand('ping').ok" 2>/dev/null | grep -q 1; then echo " ... ready"; break; fi
  echo -n "."; sleep 2
  [ "$i" -eq 40 ] && { echo; echo "MongoDB did not become ready in time."; exit 1; }
done
echo
echo "== MongoDB is running =="
mongoeval "
const b = db.adminCommand({ buildInfo: 1 });
print('MongoDB version : ' + b.version);
print('database        : ' + db.getName() + '  (created when the first data is stored)');
print('collections now : ' + db.getCollectionNames().length);
"
echo
echo "MongoDB is ready."
