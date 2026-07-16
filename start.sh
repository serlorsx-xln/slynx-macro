#!/usr/bin/env bash
# DEPRECATED — use docker compose + ./deploy.sh instead.
#
#   cd recoil/server
#   SSHPASS='...' DEPLOY_SERVER_IP=103.245.164.254 ./deploy.sh
#
# This script is kept only as a local emergency fallback. It does NOT mount
# private.pem / products / payload.ahk correctly for current production.

set -euo pipefail
cd "$(dirname "$0")"

echo "=== DEPRECATED: start.sh ==="
echo "Use:  SSHPASS=... ./deploy.sh"
echo "Or locally: docker compose up -d --build"
echo ""
echo "Continuing with legacy docker run (may be incomplete)..."
echo ""

if [ ! -f .env ]; then
  echo "[*] Generating .env from .env.example..."
  if [ -f .env.example ]; then
    cp .env.example .env
  else
    cat <<EOF > .env
PORT=8080
APP_VERSION=1.0.0
AES_SECRET_KEY=
HMAC_SECRET_SALT=
ADMIN_PASS=
LICENSE_KEY_PREFIX=SLYNX
DEFAULT_PRODUCT_ID=recoil
DISCORD_WEBHOOK=
EOF
  fi
  echo "WARNING: Edit .env with real secrets before production use."
fi

# Ensure required keys exist (do not overwrite existing values)
grep -q '^LICENSE_KEY_PREFIX=' .env || echo 'LICENSE_KEY_PREFIX=SLYNX' >> .env
grep -q '^DEFAULT_PRODUCT_ID=' .env || echo 'DEFAULT_PRODUCT_ID=recoil' >> .env

mkdir -p ./app_db
chmod 600 .env 2>/dev/null || true

if [ ! -f private.pem ]; then
  echo "ERROR: private.pem missing — required for license signing."
  exit 1
fi

docker compose down 2>/dev/null || true
docker stop macro_auth 2>/dev/null || true
docker rm macro_auth 2>/dev/null || true

echo "[1/2] Building via docker compose..."
docker compose up -d --build

echo "[2/2] Done."
echo "API: http://127.0.0.1:8081/health"
echo "Logs: docker logs -f macro_auth"
