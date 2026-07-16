#!/bin/sh
set -eu

# Write RSA private key from env (Coolify secret) when not mounted as a file.
if [ -n "${PRIVATE_PEM:-}" ] && [ ! -s /app/private.pem ]; then
  printf '%s\n' "$PRIVATE_PEM" > /app/private.pem
  chmod 600 /app/private.pem
  chown appuser:appuser /app/private.pem 2>/dev/null || true
fi

if [ ! -s /app/private.pem ]; then
  echo "ERROR: private.pem missing — set PRIVATE_PEM env or mount the file." >&2
  exit 1
fi

exec su-exec appuser ./hwid-server
