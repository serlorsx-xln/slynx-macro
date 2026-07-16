#!/bin/bash
# Generate a license key via the auth server.
#
# Usage:
#   ./gen_key.sh <admin_password> <product_id> [<days>] [<custom_key>]
#
# Examples:
#   ./gen_key.sh "$ADMIN_PASS" recoil              # lifetime
#   ./gen_key.sh "$ADMIN_PASS" recoil 30           # 30 days
#   ./gen_key.sh "$ADMIN_PASS" recoil 30 MY-KEY-01 # custom key, 30 days
#
# Run on the server for best security:
#   cd ~/Desktop/macro-server && bash gen_key.sh ...

SERVER_URL="${LICENSE_SERVER_URL:-http://127.0.0.1:8081/create_key}"

if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Error: Missing arguments."
    echo "Usage: ./gen_key.sh <admin_password> <product_id> [<days>] [<custom_key>]"
    exit 1
fi

ADMIN_PASS="$1"
PRODUCT_ID="$2"
DAYS_PARAM="${3:-}"
KEY_PARAM=""

# If 3rd arg looks like a key (contains letters and dash), treat as custom key not days
if [ -n "$3" ] && ! [[ "$3" =~ ^[0-9]+$ ]]; then
    KEY_PARAM="$3"
    DAYS_PARAM="${4:-}"
elif [ -n "$3" ]; then
    DAYS_PARAM="$3"
    KEY_PARAM="${4:-}"
fi

QUERY="?product=${PRODUCT_ID}"
[ -n "$KEY_PARAM" ]  && QUERY="${QUERY}&key=${KEY_PARAM}"
[ -n "$DAYS_PARAM" ] && QUERY="${QUERY}&days=${DAYS_PARAM}"

echo "Requesting key (product=${PRODUCT_ID})..."
RESPONSE=$(curl -s -w "\n[HTTP %{http_code}]" \
    -H "Authorization: ${ADMIN_PASS}" \
    "${SERVER_URL}${QUERY}")

if [ $? -ne 0 ]; then
    echo "Error: Failed to connect to server."
    exit 1
fi

echo -e "$RESPONSE"
