#!/bin/zsh
# Renders frames.html into the App Store highlight frames, JPEG without alpha
# (App Store Connect rejects screenshots with one):
#
#   screenshots/highlights-6.9/   2868 × 1320, the 6.9" iPhone slot
#   screenshots/highlights-ipad-13/ 2752 × 2064, the 13" iPad slot
#   …-6.3 (2622 × 1206), -6.1 (2556 × 1179), -ipad-12.9 (2732 × 2048), resized
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
  # Smaller slots take only their own sizes when they are filled in by hand.
  # Same aspect ratio within 0.2%, so a straight resize, no re-layout.
  for slot in ${@:6}; do
    set -- ${(s/:/)slot}
    mkdir -p ../screenshots/highlights-$1
    sips -s format jpeg -s formatOptions 92 -z $3 $2 $TMP/f.png --out ../screenshots/highlights-$1/0${names[$i]}.jpg >/dev/null
  done
}

for i in {1..6}; do
  render $i "" 2868 1320 ../screenshots/highlights-6.9 6.3:2622:1206 6.1:2556:1179
  render $i "&size=ipad" 2752 2064 ../screenshots/highlights-ipad-13 ipad-12.9:2732:2048
done
rm -rf $TMP
