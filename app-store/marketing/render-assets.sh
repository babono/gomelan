#!/bin/zsh
# Renders assets.html into the App Store product page header, search result
# and universal assets, each as PNG (no alpha) and JPEG:
#
#   screenshots/header/     header-3840x1646
#   screenshots/search/     search-3840x2560, search-1920x1280
#   screenshots/universal/  universal-5244x2950 — one asset for both slots
#
#   app-store/marketing/render-assets.sh          # SAFE=1 outlines the safe area
#
# The search result shows the raw captures — retake those first with
# ../capture-screenshots.sh if the app has changed.
set -euo pipefail
cd "$(dirname "$0")"

CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
TMP=$(mktemp -d)

render() {  # kind, width, height
  local out=../screenshots/$1 name=$1-$2x$3
  mkdir -p $out
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=1 \
    --allow-file-access-from-files --window-size=$2,$3 --virtual-time-budget=4000 \
    --screenshot=$TMP/a.png "file://$PWD/assets.html?kind=$1&w=$2&h=$3${SAFE:+&safe=1}" 2>/dev/null
  # App Store Connect rejects an alpha channel: through JPEG and back drops it.
  sips -s format jpeg -s formatOptions 95 $TMP/a.png --out $out/$name.jpeg >/dev/null
  sips -s format png $out/$name.jpeg --out $out/$name.png >/dev/null
  echo $out/$name.png
}

render header 3840 1646
render search 3840 2560
render search 1920 1280
render universal 5244 2950
rm -rf $TMP
