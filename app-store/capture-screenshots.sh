#!/bin/zsh
# Retakes the App Store screenshots on the 6.9" iPhone simulator — the one
# size App Store Connect requires; it scales these down for every smaller phone.
#
# Uses the DEBUG-only `-screenshot <scene>` hook (Kotek/Model/ScreenshotScenes.swift)
# to open each screen with sample data behind it. The practice screen is not
# here: the simulator has no camera, so that one is taken on a phone.
#
#   app-store/capture-screenshots.sh            # from the repo root
#   SIM=<udid> app-store/capture-screenshots.sh # a different simulator
#
# The simulator's runtime must be at least the deployment target (iOS 26.5).
set -euo pipefail
cd "$(dirname "$0")/.."

SIM=${SIM:-$(xcrun simctl list devices available | awk '/-- iOS 26.5 --/{f=1;next} /-- /{f=0} f && /iPhone 17 Pro Max/' \
  | grep -oE '[0-9A-F-]{36}' | head -1)}
[[ -n $SIM ]] || { echo "No iOS 26.5 iPhone 17 Pro Max simulator" >&2; exit 1; }
BUNDLE=$(awk -F' *= *' '/PRODUCT_BUNDLE_IDENTIFIER/{print $2}' Config.xcconfig)
DD=$(mktemp -d)
OUT=app-store/screenshots/iphone-6.9
mkdir -p $OUT

xcrun simctl boot $SIM 2>/dev/null || true
xcodegen generate -q
xcodebuild -project Kotek.xcodeproj -scheme Kotek -destination "id=$SIM" \
  -configuration Debug -derivedDataPath $DD build -quiet
xcrun simctl install $SIM $DD/Build/Products/Debug-iphonesimulator/Kotek.app
xcrun simctl status_bar $SIM override --time 9:41 --batteryState charged \
  --batteryLevel 100 --cellularBars 4 --wifiBars 3
xcrun simctl privacy $SIM grant camera $BUNDLE
xcrun simctl privacy $SIM grant microphone $BUNDLE

# Launch arguments land in UserDefaults' argument domain. Booleans have to be
# spelled as plist, or they arrive as the string "YES" and `as? Bool` misses.
T='<true/>'; F='<false/>'
L=(-AppleLocale en_US -AppleLanguages '(en)')
SEEN=($L -hasSeenOnboarding $T -hasSeenGuide $T -hasSeenGuide.kotekan $T -hasSeenPracticeCoach $T)

shot() {
  local name=$1; shift
  xcrun simctl terminate $SIM $BUNDLE 2>/dev/null || true
  xcrun simctl launch $SIM $BUNDLE "$@" >/dev/null
  sleep 11   # the splash takes its time, and the pattern has to settle
  xcrun simctl io $SIM screenshot $DD/$name.png >/dev/null 2>&1
  # App Store Connect rejects screenshots with an alpha channel, which every
  # simulator PNG has. JPEG drops it, and is a third of the size.
  sips -s format jpeg -s formatOptions 92 $DD/$name.png --out $OUT/$name.jpg >/dev/null
  echo $OUT/$name.jpg
}

shot 01-welcome                $SEEN
shot 02-interlock              $L -hasSeenOnboarding $F -onboardingPage 1
shot 03-tracking               $L -hasSeenOnboarding $F -onboardingPage 2
shot 04-choose-kotekan         -screenshot kotekan     $SEEN
shot 05-results                -screenshot results     $SEEN
shot 06-your-gangsa            -screenshot instruments $SEEN
shot 07-kotekan-guide          -screenshot guide       $SEEN
shot alt-welcome-onboarding    $L -hasSeenOnboarding $F -onboardingPage 0

rm -rf $DD
