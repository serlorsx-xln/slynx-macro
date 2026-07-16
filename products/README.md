# Per-product license delivery (fulfillment: license only)

Only products with **`fulfillment: "license"`** in the catalog need a folder here.
Other types (manual, digital, role, info) **do not** use the license server.

## Delivery modes

Set `licenseDeliveryMode` in Mongo (Admin → Products) or in the catalog seed:

| Mode | Files | `/auth` returns |
|------|--------|-----------------|
| `script` (default) | `payload.ahk` | Encrypted AutoHotkey script |
| `file` | `payload.bin` | Encrypted binary blob |
| `key_only` | `meta.json` only | Empty payload; key + HWID validation only |

```
products/
  recoil/
    meta.json       {"delivery":"script"}
    payload.ahk
  my-tool/
    meta.json       {"delivery":"key_only"}
  other-app/
    meta.json       {"delivery":"file"}
    payload.bin
```

- `productId` in Mongo **must match** the folder name.
- Keys are stored with `product_id`; `/auth` loads payload per mode.

## Automation

On every `./deploy.sh` (in `recoil/server/`):

1. Catalog seed from **`config/catalog.seed.json`** in this folder (standalone).
2. If deployed from the monorepo and `discord/config/catalog.seed.json` exists, it is copied over before sync (optional convenience).
3. `scripts/sync-product-payloads.sh` writes `config/license-products.json`, `products/<id>/meta.json`, and creates missing `payload.ahk` from template.
4. If `slynx_mongo` is running on the same VPS, delivery modes are merged from Mongo (`SYNC_FROM_BOT_MONGO=1`).

Manual run:

```bash
./scripts/sync-product-payloads.sh config/catalog.seed.json
# or
LICENSE_PRODUCT_IDS=recoil,other ./scripts/sync-product-payloads.sh
```

After editing a payload, restart the container (or wait for mtime cache refresh on next `/auth`).

## Third-party apps (key_only)

Buyers receive a key from Discord. Your app can validate via the same `/auth` POST (HMAC + key + HWID). Response includes `delivery_mode: "key_only"` and an empty encrypted payload — ignore payload and treat HTTP 200 + valid signature as success.
