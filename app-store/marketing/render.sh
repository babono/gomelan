#!/bin/zsh
# Renders frames.html into the App Store highlight frames, JPEG without alpha
# (App Store Connect rejects screenshots with one):
#
#   screenshots/highlights-6.9/   2868 × 1320, the 6.9" iPhone slot
#   screenshots/highlights-ipad-13/ 2752 × 2064, the 13" iPad slot
#
# App Store Connect scales these two down for every smaller iPhone and iPad.
#
#   app-store/marketing/render.sh
#
# Reads the raw captures in ../screenshots/iphone-6.9 and ../screenshots/ipad-13
# — retake those first with ../capture-screenshots.sh if the app has changed.
set -euo pipefail
cd "$(dirname "$0")"

CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
TMP=$(mktemp -d)
names=(1-your-gangsa-guided 2-one-note-at-a-time 3-two-halves 4-slow-to-full-speed 5-kotek-studio 6-two-players)

render() {  # frame, size query, width, height, out dir
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=1 \
    --allow-file-access-from-files --window-size=$3,$4 --virtual-time-budget=4000 \
    --screenshot=$TMP/f.png "file://$PWD/frames.html?frame=$1$2" 2>/dev/null
  mkdir -p $5
  sips -s format jpeg -s formatOptions 92 $TMP/f.png --out $5/0${names[$1]}.jpg >/dev/null
  echo $5/0${names[$1]}.jpg
}

for i in {1..6}; do
  render $i "" 2868 1320 ../screenshots/highlights-6.9
  render $i "&size=ipad" 2752 2064 ../screenshots/highlights-ipad-13
done
rm -rf $TMP
