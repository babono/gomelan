#!/bin/zsh
# Renders frames.html into the four App Store highlight frames, 2868 × 1320
# JPEG without alpha (App Store Connect rejects screenshots with one).
#
#   app-store/marketing/render.sh
#
# Reads the raw captures in ../screenshots/iphone-6.9 — retake those first with
# ../capture-screenshots.sh if the app has changed. Drop a real practice-screen
# capture in as marketing/practice.jpg and frame 2 uses it.
set -euo pipefail
cd "$(dirname "$0")"

CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
OUT=../screenshots/highlights
TMP=$(mktemp -d)
mkdir -p $OUT

names=(1-two-halves 2-follow-the-light 3-tighter-every-cycle 4-grow)
for i in 1 2 3 4; do
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=1 \
    --allow-file-access-from-files --window-size=2868,1320 --virtual-time-budget=4000 \
    --screenshot=$TMP/$i.png "file://$PWD/frames.html?frame=$i" 2>/dev/null
  sips -s format jpeg -s formatOptions 92 $TMP/$i.png --out $OUT/0${names[$i]}.jpg >/dev/null
  echo $OUT/0${names[$i]}.jpg
  # The 6.3" and 6.1" slots take only their own sizes. Their aspect ratios are
  # within 0.2% of 6.9"'s, so a straight resize is enough — no re-layout.
  for size in "6.3 1206 2622" "6.1 1179 2556"; do
    set -- ${=size}
    mkdir -p $OUT-$1
    sips -s format jpeg -s formatOptions 92 -z $2 $3 $TMP/$i.png --out $OUT-$1/0${names[$i]}.jpg >/dev/null
  done

  # iPad 13" — its own layout (?size=ipad), not a resize: 4:3 against 2.17:1.
  # 2732 × 2048 (12.9") is the same ratio, so that one is a resize.
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=1 \
    --allow-file-access-from-files --window-size=2752,2064 --virtual-time-budget=4000 \
    --screenshot=$TMP/ipad$i.png "file://$PWD/frames.html?frame=$i&size=ipad" 2>/dev/null
  mkdir -p $OUT-ipad-13 $OUT-ipad-12.9
  sips -s format jpeg -s formatOptions 92 $TMP/ipad$i.png --out $OUT-ipad-13/0${names[$i]}.jpg >/dev/null
  sips -s format jpeg -s formatOptions 92 -z 2048 2732 $TMP/ipad$i.png --out $OUT-ipad-12.9/0${names[$i]}.jpg >/dev/null
done
rm -rf $TMP
