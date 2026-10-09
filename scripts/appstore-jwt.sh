#!/usr/bin/env bash
set -euo pipefail

# Generate an App Store Connect JWT for API authentication.
#
# Usage:
#   source scripts/appstore-jwt.sh
#   JWT=$(jwt_token "/path/to/key.p8" "$APPSTORE_KEY_ID" "$APPSTORE_ISSUER_ID")

base64url() {
    base64 | tr '+/' '-_' | tr -d '=' | tr -d '\n'
}

jwt_token() {
    local key_path="$1"
    local key_id="$2"
    local issuer_id="$3"

    local tmp_dir
    tmp_dir="$(mktemp -d)"
    trap 'rm -rf "$tmp_dir"' RETURN

    local header payload now exp signing_input sig_file r_pad s_pad signature
    local r_orig_len r_start r_byte_len r_total s_offset s_len s_start

    header="$(printf '{"alg":"ES256","kid":"%s","typ":"JWT"}' "$key_id" | base64url)"
    now="$(date +%s)"
    exp="$((now + 600))"
    payload="$(printf '{"iss":"%s","iat":%d,"exp":%d,"aud":"appstoreconnect-v1"}' \
        "$issuer_id" "$now" "$exp" | base64url)"
    signing_input="${header}.${payload}"

    printf '%s' "$signing_input" | openssl dgst -sha256 -binary -sign "$key_path" > "$tmp_dir/sig.der"
    sig_file="$tmp_dir/sig.der"

    r_orig_len=$(dd if="$sig_file" bs=1 skip=3 count=1 2>/dev/null | od -A n -t u1 | tr -d ' \n')
    r_start=4
    r_byte_len="$r_orig_len"
    if [ "$r_orig_len" -eq 33 ]; then
        r_start=5
        r_byte_len=32
    fi
    dd if="$sig_file" bs=1 skip="$r_start" count="$r_byte_len" of="$tmp_dir/r.bin" 2>/dev/null

    local r_size
    r_size=$(wc -c < "$tmp_dir/r.bin" | tr -d ' ')
    r_pad="$tmp_dir/r_pad.bin"
    if [ "$r_size" -lt 32 ]; then
        dd if=/dev/zero bs=1 count=$((32 - r_size)) 2>/dev/null > "$r_pad"
        cat "$tmp_dir/r.bin" >> "$r_pad"
    else
        cp "$tmp_dir/r.bin" "$r_pad"
    fi

    r_total=$((2 + r_orig_len))
    s_offset=$((2 + r_total))
    s_len=$(dd if="$sig_file" bs=1 skip=$((s_offset + 1)) count=1 2>/dev/null | od -A n -t u1 | tr -d ' \n')
    s_start=$((s_offset + 2))
    if [ "$s_len" -eq 33 ]; then
        s_start=$((s_start + 1))
        s_len=32
    fi
    dd if="$sig_file" bs=1 skip="$s_start" count="$s_len" of="$tmp_dir/s.bin" 2>/dev/null

    local s_size
    s_size=$(wc -c < "$tmp_dir/s.bin" | tr -d ' ')
    s_pad="$tmp_dir/s_pad.bin"
    if [ "$s_size" -lt 32 ]; then
        dd if=/dev/zero bs=1 count=$((32 - s_size)) 2>/dev/null > "$s_pad"
        cat "$tmp_dir/s.bin" >> "$s_pad"
    else
        cp "$tmp_dir/s.bin" "$s_pad"
    fi

    signature=$(cat "$r_pad" "$s_pad" | base64url)
    echo "${header}.${payload}.${signature}"
}
