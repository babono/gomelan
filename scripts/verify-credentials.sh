#!/usr/bin/env bash
set -euo pipefail

# Verify App Store Connect credentials are valid for TestFlight release.
# Uses JWT + curl (no xcrun dependency, works on any Mac).
#
# Usage:
#   export APPSTORE_KEY_ID="ABC123XYZ"
#   export APPSTORE_ISSUER_ID="XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX"
#   scripts/verify-credentials.sh

msg()   { printf "  %s\n" "$1"; }
pass()  { printf "  \033[0;32m✓\033[0m %s\n" "$1"; }
fail()  { printf "  \033[0;31m✗\033[0m %s\n" "$1"; EXIT=1; }

EXIT=0
cleanup() { rm -f "${TMP_DIR:-/tmp/notset}"/* 2>/dev/null; rmdir "${TMP_DIR:-/tmp/notset}" 2>/dev/null || true; }
trap cleanup EXIT

echo "=== App Store Connect Credential Check ==="
echo ""

# ── Prerequisite tools ─────────────────────────────────────
for cmd in openssl curl base64; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        fail "${cmd}: not found (required)"
    fi
done
if [[ $EXIT -ne 0 ]]; then exit 1; fi

# ── Environment variables ──────────────────────────────────
if [[ -z "${APPSTORE_KEY_ID:-}" ]]; then
    fail "APPSTORE_KEY_ID: not set"
    echo ""
    echo "  Fix: export APPSTORE_KEY_ID=\"YOUR_KEY_ID\""
else
    pass "APPSTORE_KEY_ID: ${APPSTORE_KEY_ID}"
fi

if [[ -z "${APPSTORE_ISSUER_ID:-}" ]]; then
    fail "APPSTORE_ISSUER_ID: not set"
    echo ""
    echo "  Fix: export APPSTORE_ISSUER_ID=\"XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX\""
else
    pass "APPSTORE_ISSUER_ID: set"
fi
if [[ $EXIT -ne 0 ]]; then exit 1; fi

# ── Key file ────────────────────────────────────────────────
KEY_DIR="${HOME}/.appstoreconnect"
KEY_PATH="${KEY_DIR}/AuthKey_${APPSTORE_KEY_ID}.p8"

if [[ ! -f "${KEY_PATH}" ]]; then
    fail "Key file not found: ${KEY_PATH}"
    echo ""
    echo "  Fix: Save your .p8 key file to ${KEY_PATH}"
    echo "       cp ~/Downloads/AuthKey_${APPSTORE_KEY_ID}.p8 ${KEY_PATH}"
    exit 1
fi
pass "Key file exists: ${KEY_PATH}"

KEY_SIZE="$(wc -c < "${KEY_PATH}" | tr -d ' ')"
if [[ "${KEY_SIZE}" -lt 20 ]]; then
    fail "Key file too small: ${KEY_SIZE} bytes (expected ~160+ bytes)"
    exit 1
fi
pass "Key file: ${KEY_SIZE} bytes"

KEY_PERMS="$(stat -f '%Lp' "${KEY_PATH}" 2>/dev/null || stat -c '%a' "${KEY_PATH}" 2>/dev/null || echo "???")"
if [[ "${KEY_PERMS}" != "600" ]]; then
    chmod 600 "${KEY_PATH}"
    pass "Key file permissions fixed: 600"
else
    pass "Key file permissions: 600"
fi

if ! grep -q "BEGIN PRIVATE KEY" "${KEY_PATH}" 2>/dev/null; then
    fail "Key file does not contain 'BEGIN PRIVATE KEY' header"
    exit 1
fi

# ── Generate JWT ────────────────────────────────────────────
echo ""
echo "--- JWT + API authentication ---"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/appstore-jwt.sh
source "${SCRIPT_DIR}/appstore-jwt.sh"

JWT=$(jwt_token "${KEY_PATH}" "${APPSTORE_KEY_ID}" "${APPSTORE_ISSUER_ID}")
pass "JWT generated"

TMP_DIR="$(mktemp -d)"

# ── Test authentication via App Store Connect API ───────────
HTTP_CODE=$(curl -s -o "${TMP_DIR}/response.json" -w '%{http_code}' \
    -H "Authorization: Bearer ${JWT}" \
    "https://api.appstoreconnect.apple.com/v1/apps?limit=1" 2>/dev/null || echo "000")

case "${HTTP_CODE}" in
    200)
        pass "App Store Connect API: authenticated (200)"
        APP_COUNT=$(python3 -c "
import json, sys
d = json.load(open('${TMP_DIR}/response.json'))
print(len(d.get('data', [])))
" 2>/dev/null || echo "?")
        msg "  Found ${APP_COUNT} apps for this team"
        ;;
    401)
        fail "App Store Connect API: 401 Unauthorized"
        echo ""
        echo "  Possible causes:"
        echo "    - Key ID or Issuer ID does not match the .p8 file"
        echo "    - Key has expired (check Status in App Store Connect)"
        echo "    - Key role must be 'Admin' or 'App Manager'"
        echo ""
        echo "  Check at: https://appstoreconnect.apple.com/access/integrations/api"
        exit 1
        ;;
    403)
        fail "App Store Connect API: 403 Forbidden"
        echo ""
        echo "  Possible causes:"
        echo "    - API key exists but has insufficient permissions"
        echo "    - The Apple ID that created the key does not have team access"
        echo ""
        echo "  Fix: Recreate key with 'Admin' role in App Store Connect"
        exit 1
        ;;
    *)
        fail "App Store Connect API: HTTP ${HTTP_CODE}"
        if [[ -s "${TMP_DIR}/response.json" ]]; then
            echo ""
            echo "  Response:"
            head -c 500 "${TMP_DIR}/response.json"
        fi
        exit 1
        ;;
esac

echo ""
echo "=== All checks passed — credentials are valid ==="
