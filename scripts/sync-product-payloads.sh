#!/usr/bin/env bash
# Sync license products: catalog JSON, meta.json, and payload files.
#
# Delivery modes (Mongo licenseDeliveryMode / seed licenseDeliveryMode):
#   script   — products/<id>/payload.ahk  (AutoHotkey / Slynx client)
#   file     — products/<id>/payload.bin  (generic binary on /auth)
#   key_only — no payload file; key validation only
#
# Usage:
#   ./scripts/sync-product-payloads.sh [path/to/catalog.seed.json]
#   LICENSE_PRODUCT_IDS=recoil,other ./scripts/sync-product-payloads.sh
#
# Template for new script dirs: PAYLOAD_TEMPLATE=./payload.ahk (default)

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED_FILE="${1:-config/catalog.seed.json}"
TEMPLATE="${PAYLOAD_TEMPLATE:-./payload.ahk}"
CATALOG_OUT="config/license-products.json"

license_rows_from_mongo() {
  if [ "${SYNC_FROM_BOT_MONGO:-}" != "1" ] || ! command -v docker >/dev/null 2>&1; then
    return 0
  fi
  docker ps --format '{{.Names}}' 2>/dev/null | grep -q '^slynx_mongo$' || return 0
  docker exec slynx_mongo mongosh --quiet slynx --eval \
    'db.products.find({fulfillment:"license"},{productId:1,licenseDeliveryMode:1,_id:0}).forEach(function(p){
      var mode = (p.licenseDeliveryMode || "script").toString().toLowerCase();
      print(p.productId + "\t" + mode);
    })' 2>/dev/null \
    | tr '[:upper:]' '[:lower:]' | sed '/^$/d' || true
}

license_rows_from_seed() {
  [ -f "$SEED_FILE" ] || return 0
  python3 - "$SEED_FILE" <<'PY'
import json, sys
path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    data = json.load(f)
if not isinstance(data, list):
    raise SystemExit("catalog seed must be a JSON array")
for p in data:
    if not isinstance(p, dict):
        continue
    fid = str(p.get("productId", "")).strip().lower()
    if not fid:
        continue
    fulfillment = str(p.get("fulfillment", "license")).strip().lower()
    if fulfillment != "license":
        continue
    mode = str(p.get("licenseDeliveryMode", "script")).strip().lower() or "script"
    print(f"{fid}\t{mode}")
PY
}

normalize_mode() {
  case "$(echo "$1" | tr '[:upper:]' '[:lower:]' | tr '-' '_')" in
    key_only|keyonly) echo "key_only" ;;
    file|binary|payload) echo "file" ;;
    *) echo "script" ;;
  esac
}

# Build merged rows in a temp file (seed first, mongo overwrites mode)
TMP_ROWS="$(mktemp)"
trap 'rm -f "$TMP_ROWS"' EXIT

if [ -n "${LICENSE_PRODUCT_IDS:-}" ]; then
  echo "$LICENSE_PRODUCT_IDS" | tr ',' '\n' | tr '[:upper:]' '[:lower:]' | sed '/^$/d' | while IFS= read -r pid; do
    [ -z "$pid" ] && continue
    printf '%s\tscript\n' "$pid"
  done > "$TMP_ROWS"
else
  {
    license_rows_from_seed
    license_rows_from_mongo
  } | awk -F'\t' '
    {
      id=$1; mode=$2;
      if (id=="") next;
      if (mode=="") mode="script";
      if (!(id in modes)) order[++n]=id;
      modes[id]=mode;
    }
    END { for (i=1;i<=n;i++) print order[i] "\t" modes[order[i]]; }
  ' > "$TMP_ROWS"
fi

mkdir -p config products

# Write config/license-products.json
python3 - "$TMP_ROWS" "$CATALOG_OUT" <<'PY'
import json, sys
rows_path, out_path = sys.argv[1], sys.argv[2]
catalog = {}
with open(rows_path, encoding="utf-8") as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        parts = line.split("\t", 1)
        pid = parts[0].strip().lower()
        mode = (parts[1].strip() if len(parts) > 1 else "script") or "script"
        if pid:
            catalog[pid] = {"delivery": mode}
with open(out_path, "w", encoding="utf-8") as f:
    json.dump(catalog, f, indent=2, sort_keys=True)
    f.write("\n")
print(f"  CAT {out_path} ({len(catalog)} product(s))")
PY

created=0
skipped=0
warn=0
fail=0

while IFS=$'\t' read -r pid mode; do
  [ -z "$pid" ] && continue
  mode="$(normalize_mode "$mode")"
  dir="products/${pid}"
  mkdir -p "$dir"

  meta="${dir}/meta.json"
  printf '{"delivery":"%s"}\n' "$mode" > "$meta"
  echo "  META $meta ($mode)"

  case "$mode" in
    key_only)
      skipped=$((skipped + 1))
      ;;
    file)
      dest="${dir}/payload.bin"
      if [ -f "$dest" ]; then
        echo "  OK  $dest"
        skipped=$((skipped + 1))
      else
        echo "  WARN missing $dest (upload binary before selling)" >&2
        warn=$((warn + 1))
      fi
      ;;
    script|*)
      dest="${dir}/payload.ahk"
      if [ -f "$dest" ]; then
        echo "  OK  $dest"
        skipped=$((skipped + 1))
      elif [ -f "$TEMPLATE" ]; then
        cp "$TEMPLATE" "$dest"
        echo "  NEW $dest (from $TEMPLATE)"
        created=$((created + 1))
      else
        echo "  WARN missing $dest and no template at $TEMPLATE" >&2
        warn=$((warn + 1))
        fail=$((fail + 1))
      fi
      ;;
  esac
done < "$TMP_ROWS"

echo "sync-product-payloads: created=$created existing=$skipped warn=$warn"
[ "$fail" -eq 0 ] || exit 1
