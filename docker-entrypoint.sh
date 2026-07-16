#!/bin/sh
set -eu

# Write RSA private key from env (Coolify secret) when not mounted as a file.
if [ -n "${PRIVATE_PEM:-}" ] && [ ! -s /app/private.pem ]; then
  # Coolify / some UIs store newlines as literal \n - expand before write.
  printf '%s\n' "$PRIVATE_PEM" | sed 's/\\n/\n/g' > /app/private.pem
  chmod 600 /app/private.pem
  chown appuser:appuser /app/private.pem 2>/dev/null || true
fi

if [ ! -s /app/private.pem ]; then
  echo "ERROR: private.pem missing - set PRIVATE_PEM env or mount the file." >&2
  exit 1
fi

if ! grep -q "BEGIN.*PRIVATE KEY" /app/private.pem 2>/dev/null; then
  echo "ERROR: private.pem does not look like a PEM private key." >&2
  exit 1
fi

# Seed / refresh auto-update binary from ./seed/client.exe (bind-mounted).
# Does not wipe licenses.db in the named volume.
mkdir -p /app/db
if [ -f /seed/client.exe ]; then
  cp -f /seed/client.exe /app/db/client.exe
  chmod 644 /app/db/client.exe
  chown appuser:appuser /app/db/client.exe 2>/dev/null || true
fi
chown -R appuser:appuser /app/db 2>/dev/null || true

exec su-exec appuser ./hwid-server
