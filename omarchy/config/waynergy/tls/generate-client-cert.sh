#!/usr/bin/env bash
# Create the PEM Waynergy sends when Deskflow requires a client certificate.
set -euo pipefail

tls_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
pem="$tls_dir/cert"
cnf="$tls_dir/openssl.cnf"

if [[ ! -f "$cnf" ]]; then
  printf 'Missing %s; run the repository installer first.\n' "$cnf" >&2
  exit 1
fi
if [[ -e "$pem" ]]; then
  printf '%s already exists; move it aside explicitly before rotating it.\n' "$pem" >&2
  exit 1
fi

openssl req -x509 -nodes -days 3650 \
  -newkey rsa:2048 \
  -keyout "$pem" \
  -out "$pem" \
  -config "$cnf"

chmod 600 "$pem"
printf 'Wrote %s\n\n' "$pem"
printf '%s\n' 'Client SHA-256 fingerprint (approve this on the Deskflow server if asked):'
openssl x509 -fingerprint -sha256 -noout -in "$pem"
