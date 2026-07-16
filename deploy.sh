#!/usr/bin/env bash
# Deploy license auth server to production (standalone — does not require Discord bot)
# Usage:
#   ./deploy.sh
#   SSHPASS='password' DEPLOY_SERVER_IP=103.245.164.254 ./deploy.sh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${ROOT_DIR}/../.." && pwd)"
DISCORD_SEED="${REPO_ROOT}/discord/config/catalog.seed.json"
LIB="${REPO_ROOT}/scripts/deploy/lib.sh"

# shellcheck source=/dev/null
source "$LIB"

SERVER_PATH_RSYNC="~/Desktop/macro-server"
SERVER_PATH_SSH='$HOME/Desktop/macro-server'

deploy_ssh_init

deploy_require_file "${ROOT_DIR}/.env" "copy from .env.example"
deploy_require_file "${ROOT_DIR}/private.pem" "required for license signing"
deploy_require_env_key "${ROOT_DIR}/.env" ADMIN_PASS

echo ""
echo "=== License Auth Server Deploy ==="
echo "  Target: ${DEPLOY_USER}@${DEPLOY_SERVER_IP}"
echo ""

# Optional monorepo convenience — local server seed is primary for standalone sale
if [ -f "$DISCORD_SEED" ]; then
  mkdir -p "${ROOT_DIR}/config"
  cp "$DISCORD_SEED" "${ROOT_DIR}/config/catalog.seed.json"
  echo "  Catalog seed synced from discord/config/catalog.seed.json (monorepo)"
fi
deploy_require_file "${ROOT_DIR}/config/catalog.seed.json" "add config/catalog.seed.json or LICENSE_PRODUCT_IDS"

chmod +x "${ROOT_DIR}/scripts/sync-product-payloads.sh" 2>/dev/null || true

deploy_bootstrap_remote "~/Desktop/macro-server"

echo "[1/3] Syncing server files..."
deploy_rsync "${ROOT_DIR}/" "${SERVER_PATH_RSYNC}/" \
  --exclude='.DS_Store' \
  --exclude='app_db/' \
  --exclude='build/' \
  --exclude='*.exe' \
  --exclude='main' \
  --exclude='server' \
  --exclude='server_release' \
  --exclude='licenses.db' \
  --exclude='licenses.db-shm' \
  --exclude='licenses.db-wal'

echo "  Files synced (.env + private.pem included)."

# Sync auto-update binary only (do not sync whole app_db — preserves licenses.db)
if [ -f "${ROOT_DIR}/app_db/client.exe" ]; then
  echo "  Syncing app_db/client.exe for /update..."
  deploy_remote_exec "mkdir -p ~/Desktop/macro-server/app_db"
  deploy_rsync "${ROOT_DIR}/app_db/client.exe" "~/Desktop/macro-server/app_db/client.exe"
else
  echo "  Warning: app_db/client.exe missing — run ../build_release.sh before deploy for auto-update"
fi

echo ""
echo "[2/3] Preparing products and permissions..."
deploy_remote_exec "bash -s" <<'REMOTE'
set -euo pipefail
cd ~/Desktop/macro-server
mkdir -p app_db
chmod 600 .env 2>/dev/null || true
chown 1001:1001 app_db private.pem 2>/dev/null || true
chmod 750 app_db 2>/dev/null || true
chmod 600 private.pem payload.ahk 2>/dev/null || true
if [ -f app_db/client.exe ]; then
  chown 1001:1001 app_db/client.exe 2>/dev/null || true
  chmod 644 app_db/client.exe 2>/dev/null || true
fi
test -f payload.ahk || cp macro.ahk payload.ahk 2>/dev/null || true
chmod +x scripts/sync-product-payloads.sh 2>/dev/null || true
SYNC_FROM_BOT_MONGO=0
if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx 'slynx_mongo'; then
  echo "  slynx_mongo running — merging license delivery modes from Mongo"
  SYNC_FROM_BOT_MONGO=1
fi
SYNC_FROM_BOT_MONGO=$SYNC_FROM_BOT_MONGO ./scripts/sync-product-payloads.sh config/catalog.seed.json
chown 1001:1001 app_db private.pem products 2>/dev/null || true
find products -type f -exec chown 1001:1001 {} + 2>/dev/null || true
REMOTE

echo ""
echo "[3/3] Building and starting macro_auth..."
deploy_remote_exec "bash -s" <<'REMOTE'
set -euo pipefail
cd ~/Desktop/macro-server
mkdir -p ./app_db
chown 1001:1001 app_db private.pem 2>/dev/null || true
chmod 750 app_db 2>/dev/null || true
docker compose down 2>/dev/null || true
docker compose up -d --build
REMOTE

deploy_wait_container_healthy macro_auth 120

echo ""
echo "=== Deploy complete ==="
echo ""
echo "  API:       http://${DEPLOY_SERVER_IP}:8081"
echo "  Health:    curl http://${DEPLOY_SERVER_IP}:8081/health"
echo "  Logs:      ssh ${DEPLOY_USER}@${DEPLOY_SERVER_IP} 'docker logs -f macro_auth'"
echo ""
