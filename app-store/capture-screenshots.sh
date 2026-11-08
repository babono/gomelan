#!/bin/zsh
# Retakes the App Store screenshots on the two simulators App Store Connect
# asks for: the 6.9" iPhone (it scales these for every smaller phone) and the
# 13" iPad. Landscape, 2868 × 1320 and 2752 × 2064, JPEG without alpha.
#
# Uses the DEBUG-only `-screenshot <scene>` hook (Kotek/Core/Models/ScreenshotScenes.swift)
# to open each screen with sample data behind it. Nothing needs a gangsa or a
# strike controller: free play runs unscored, and the bars play themselves.
#
#   app-store/capture-screenshots.sh              # both devices
#   DEVICES=iphone app-store/capture-screenshots.sh
#
# The simulators' runtime must be at least the deployment target (iOS 26.5).
set -euo pipefail
cd "$(dirname "$0")/.."

udid() {
  xcrun simctl list devices available | awk '/-- iOS 26.5 --/{f=1;next} /-- /{f=0} f' \
    | grep "$1 (" | grep -oE '[0-9A-F-]{36}' | head -1
}
BUNDLE=$(awk -F' *= *' '/PRODUCT_BUNDLE_IDENTIFIER/{print $2}' Config.xcconfig)
DD=$(mktemp -d)

xcodegen generate -q
xcodebuild -project Kotek.xcodeproj -scheme Kotek -destination 'generic/platform=iOS Simulator' \
  -configuration Debug -derivedDataPath $DD build -quiet
APP=$DD/Build/Products/Debug-iphonesimulator/Kotek.app

# Launch arguments land in UserDefaults' argument domain. Booleans have to be
# spelled as plist, or they arrive as the string "YES" and `as? Bool` misses.
T='<true/>'
L=(-AppleLocale en_US -AppleLanguages '(en)')
SEEN=($L -hasSeenOnboarding $T -hasSeenGuide $T -hasSeenGuide.kotekan $T -hasSeenFreePlayTour $T)

shot() {
  local name=$1 wait=$2; shift 2
  xcrun simctl terminate $SIM $BUNDLE 2>/dev/null || true
  xcrun simctl launch $SIM $BUNDLE "$@" >/dev/null
  sleep $wait   # the splash, then whatever the screen has to get going
  xcrun simctl io $SIM screenshot $DD/$name.png >/dev/null 2>&1
  if [[ $device == ipad ]]; then
    # `simctl` cannot turn a device, and the simulator iPad stands upright,
    # so this landscape-only app comes out letterboxed: a 2064 × 1548 picture
    # (exactly 4:3) between black bars. Cut it out and scale it to the 13"
    # slot's 2752 × 2064. Asking the scene to rotate (requestGeometryUpdate)
    # did not move it.
    sips -c 1548 2064 --cropOffset 602 0 $DD/$name.png --out $DD/$name.png >/dev/null
    sips -z 2064 2752 $DD/$name.png --out $DD/$name.png >/dev/null
  fi
  # App Store Connect rejects screenshots with an alpha channel, which every
  # simulator PNG has. JPEG drops it, and is a third of the size.
  sips -s format jpeg -s formatOptions 92 $DD/$name.png --out $OUT/$name.jpg >/dev/null
  echo $OUT/$name.jpg
}

for device in ${=DEVICES:-iphone ipad}; do
  case $device in
    iphone) SIM=$(udid "iPhone 17 Pro Max"); OUT=app-store/screenshots/iphone-6.9 ;;
    ipad)   SIM=$(udid "iPad Pro 13-inch (M5)"); OUT=app-store/screenshots/ipad-13 ;;
  esac
  [[ -n $SIM ]] || { echo "No iOS 26.5 simulator for $device" >&2; exit 1; }
  mkdir -p $OUT
  xcrun simctl boot $SIM 2>/dev/null || true
  xcrun simctl bootstatus $SIM -b >/dev/null
  xcrun simctl install $SIM $APP
  xcrun simctl status_bar $SIM override --time 9:41 --batteryState charged \
    --batteryLevel 100 --cellularBars 4 --wifiBars 3

  # Free play mid-figure: past the count-in, notes on the rail.
  shot 01-play           24 -screenshot waterfall         $SEEN
  shot 02-note-by-note   16 -screenshot learn-step        $SEEN
  shot 03-two-halves     14 -screenshot learn             $SEEN
  shot 04-build-up       18 -screenshot learn-buildup     $SEEN
  shot 05-studio         14 -screenshot create-polos-roll $SEEN
  shot 06-coop           18 -screenshot coop              $SEEN
  shot 07-choose-kotekan 12 -screenshot kotekan           $SEEN
  shot 08-welcome        12                               $SEEN
  shot 09-kotekan-guide  12 -screenshot guide             $SEEN
  # ponytail: no results shot. In the simulator Kipli's Apple Intelligence
  # overview never finishes, and "Let me look back over your session…" is
  # not a screen to sell with.
  xcrun simctl shutdown $SIM
done
rm -rf $DD
