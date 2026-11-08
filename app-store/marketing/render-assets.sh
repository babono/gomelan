#!/bin/zsh
# Renders assets.html into the App Store product page header and search
# result assets, JPEG without alpha:
#
#   screenshots/header/   5244 × 2950 (also usable as search: universal), 3840 × 1646
#   screenshots/search/   5244 × 2950, 3840 × 2560, 1920 × 1280
#
#   app-store/marketing/render-assets.sh
#
# The search result shows the raw captures — retake those first with
# ../capture-screenshots.sh if the app has changed.
set -euo pipefail
cd "$(dirname "$0")"

CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
TMP=$(mktemp -d)

render() {  # kind, width, height
  local out=../screenshots/$1
  mkdir -p $out
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=1 \
    --allow-file-access-from-files --window-size=$2,$3 --virtual-time-budget=4000 \
    --screenshot=$TMP/a.png "file://$PWD/assets.html?kind=$1&w=$2&h=$3" 2>/dev/null
  sips -s format jpeg -s formatOptions 92 $TMP/a.png --out $out/$1-$2x$3.jpg >/dev/null
  echo $out/$1-$2x$3.jpg
}

render header 5244 2950
render header 3840 1646
render search 5244 2950
render search 3840 2560
render search 1920 1280
rm -rf $TMP
