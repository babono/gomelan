#!/usr/bin/env bash
set -euo pipefail

# Test the App Store Connect build number query locally.
# Uses the same JWT + curl logic as the CI workflow.
#
# Usage:
#   export APPSTORE_KEY_ID="ABC123XYZ"
#   export APPSTORE_ISSUER_ID="XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX"
#   scripts/test-asc-build.sh

pass() { printf "  \033[0;32m✓\033[0m %s\n" "$1"; }
fail() { printf "  \033[0;31m✗\033[0m %s\n" "$1"; }
info() { printf "  → %s\n" "$1"; }

echo "=== ASC Build Query Test ==="
echo ""

# ── Prerequisites ─────────────────────────────────────────
if [[ -z "${APPSTORE_KEY_ID:-}" ]]; then
    fail "APPSTORE_KEY_ID: not set"
    echo "  export APPSTORE_KEY_ID=\"YOUR_KEY_ID\""
    exit 1
fi

if [[ -z "${APPSTORE_ISSUER_ID:-}" ]]; then
    fail "APPSTORE_ISSUER_ID: not set"
    echo "  export APPSTORE_ISSUER_ID=\"UUID\""
    exit 1
fi

KEY_PATH="${HOME}/.appstoreconnect/AuthKey_${APPSTORE_KEY_ID}.p8"
if [[ ! -f "${KEY_PATH}" ]]; then
    fail "Key file not found: ${KEY_PATH}"
    exit 1
fi

for cmd in openssl curl base64 python3; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        fail "${cmd}: not found"
        exit 1
    fi
done

# ── Generate JWT ─────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/appstore-jwt.sh"

JWT=$(jwt_token "${KEY_PATH}" "${APPSTORE_KEY_ID}" "${APPSTORE_ISSUER_ID}")
JWT_LEN=$(printf '%s' "${JWT}" | wc -c | tr -d ' ')
if [ "${JWT_LEN}" -lt 100 ]; then
    fail "JWT too short: ${JWT_LEN} chars (expected ~600+)"
    exit 1
fi
pass "JWT generated (${JWT_LEN} chars)"

# ── Fetch app ID ─────────────────────────────────────────
info "Checking connectivity to App Store Connect..."
if ! curl -sf --connect-timeout 10 "https://api.appstoreconnect.apple.com" > /dev/null 2>&1; then
    fail "Cannot reach api.appstoreconnect.apple.com"
    echo ""
    echo "  Common causes:"
    echo "    - VPN or proxy blocking outbound"
    echo "    - DNS resolution failure"
    echo "    - Firewall restrictions"
    echo ""
    echo "  Run: curl -v https://api.appstoreconnect.apple.com"
    exit 1
fi
pass "Connectivity OK"

info "GET /v1/apps?filter[bundleId]=me.babono.kotek"

APPS_OUT=$(mktemp)
APPS_HTTP=$(curl -s -o "${APPS_OUT}" -w '%{http_code}' \
    -H "Authorization: Bearer ${JWT}" \
    "https://api.appstoreconnect.apple.com/v1/apps?filter%5BbundleId%5D=me.babono.kotek&limit=1" 2>/dev/null || echo "000")

case "${APPS_HTTP}" in
    200) ;;
    401)
        fail "HTTP 401 — API key is invalid or has wrong permissions."
        echo "  Fix: Verify key ID, Issuer ID, and that key has Admin role."
        exit 1
        ;;
    403)
        fail "HTTP 403 — API key lacks access to this team."
        exit 1
        ;;
    *)
        fail "HTTP ${APPS_HTTP} — unexpected response from App Store Connect."
        echo "  Response body:"
        head -c 500 "${APPS_OUT}" 2>/dev/null || true

        if [ "${APPS_HTTP}" = "000" ]; then
            echo ""
            echo "  Retrying with verbose output to diagnose..."
            echo ""
            curl -v -H "Authorization: Bearer ${JWT}" \
              "https://api.appstoreconnect.apple.com/v1/apps?filter%5BbundleId%5D=me.babono.kotek&limit=1" 2>&1 | head -50
        fi
        exit 1
        ;;
esac

APP_ID=$(python3 -c "import json,sys; d=json.load(sys.stdin); ds=d.get('data',[]); print(ds[0]['id']) if ds else sys.exit(1)" < "${APPS_OUT}")
pass "App ID: ${APP_ID}"

# ── Fetch latest build ───────────────────────────────────
info "GET /v1/builds?filter[app]=${APP_ID}&sort=-version"

BUILDS_OUT=$(mktemp)
BUILDS_HTTP=$(curl -s -o "${BUILDS_OUT}" -w '%{http_code}' \
    -H "Authorization: Bearer ${JWT}" \
    "https://api.appstoreconnect.apple.com/v1/builds?filter%5Bapp%5D=${APP_ID}&sort=-version&limit=1" 2>/dev/null || echo "000")

if [ "${BUILDS_HTTP}" != "200" ]; then
    fail "HTTP ${BUILDS_HTTP} — could not fetch builds."
    head -c 500 "${BUILDS_OUT}" 2>/dev/null || true
    exit 1
fi

LATEST=$(python3 -c "import json,sys; d=json.load(sys.stdin); ds=d.get('data',[]); print(ds[0]['attributes']['version']) if ds else print('0')" < "${BUILDS_OUT}")

if [ "${LATEST}" = "0" ]; then
    pass "No builds found yet (this is normal for a new app)"
else
    pass "Latest build: ${LATEST}"
fi

echo ""
echo "=== Latest TestFlight build: ${LATEST} ==="
