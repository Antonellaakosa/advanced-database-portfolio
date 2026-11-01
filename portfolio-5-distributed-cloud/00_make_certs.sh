#!/usr/bin/env bash
# =====================================================================
# UPLN | MIT 8103 | Portfolio 5
# File    : 00_make_certs.sh
# Purpose : Creates (1) a private certificate authority and one server
#           certificate for the lab nodes, so every connection can use TLS,
#           and (2) random passwords in .env.p5.
#           Both are listed in .gitignore: secrets never go into GitHub.
# Run     : bash portfolio-5-distributed-cloud/00_make_certs.sh
# =====================================================================
set -eu
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CERTS="$HERE/certs"; ENVF="$HERE/.env.p5"
mkdir -p "$CERTS"

if [ ! -s "$CERTS/server.crt" ]; then
  echo "Creating the certificate authority and the server certificate..."
  openssl genrsa -out "$CERTS/ca.key" 4096 2>/dev/null
  openssl req -x509 -new -nodes -key "$CERTS/ca.key" -sha256 -days 365 -subj "/O=UPLN Lab/CN=UPLN Lab CA" -out "$CERTS/ca.crt"
  openssl genrsa -out "$CERTS/server.key" 2048 2>/dev/null
  openssl req -new -key "$CERTS/server.key" -subj "/O=UPLN Lab/CN=localhost" -out "$CERTS/server.csr"
  printf "subjectAltName=DNS:localhost,DNS:primary,DNS:replica,DNS:shard_north,DNS:shard_south,IP:127.0.0.1\nextendedKeyUsage=serverAuth\n" > "$CERTS/san.cnf"
  openssl x509 -req -in "$CERTS/server.csr" -CA "$CERTS/ca.crt" -CAkey "$CERTS/ca.key" -CAcreateserial \
          -out "$CERTS/server.crt" -days 365 -sha256 -extfile "$CERTS/san.cnf" 2>/dev/null
  rm -f "$CERTS/server.csr" "$CERTS/san.cnf" "$CERTS/ca.srl"
  chmod 644 "$CERTS/ca.crt" "$CERTS/server.crt"; chmod 600 "$CERTS/server.key" "$CERTS/ca.key"
else
  echo "Certificates already exist (kept)."
fi

if [ ! -s "$ENVF" ]; then
  echo "Creating random passwords in .env.p5 ..."
  pw() { openssl rand -base64 18 | tr -d '/+=\n' | cut -c1-20; }
  {
    echo "ADMIN_PW=$(pw)"
    echo "REPL_PW=$(pw)"
    echo "APP_PW=$(pw)"
    echo "REPORT_PW=$(pw)"
    echo "FDW_PW=$(pw)"
  } > "$ENVF"
  chmod 600 "$ENVF"
else
  echo "Passwords already exist in .env.p5 (kept)."
fi
echo "Done. These files stay on your machine only:  certs/   .env.p5"
