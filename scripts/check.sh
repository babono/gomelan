#!/usr/bin/env bash
set -euo pipefail

scripts/lint.sh
xcodebuild build \
  -project Kotek.xcodeproj \
  -scheme Kotek \
  -configuration Debug \
  -destination generic/platform=iOS \
  CODE_SIGNING_ALLOWED=NO
