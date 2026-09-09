#!/bin/sh
#
# Build ECLHello and run it in the iOS Simulator.
#
#   ./run-sim.sh                 # first available iPhone simulator
#   ./run-sim.sh "iPhone 17"     # by name
#   ./run-sim.sh <udid>          # by udid, from `xcrun simctl list devices`
#
# Requires ../ecl-iOS-sim, i.e. run ../build.sh first. No code signing and no
# developer account involved -- the simulator needs neither.

set -e

cd "`dirname "$0"`"

BUNDLE_ID=org.ecl.ECLHello

if [ ! -d ../ecl-iOS-sim/lib ]; then
  echo "../ecl-iOS-sim not found -- run ../build.sh first." >&2
  exit 1
fi

WANTED="$1"
SIM=`xcrun simctl list devices available 2>/dev/null | awk -v want="$WANTED" '
    /^ *iPhone/ {
      if (want != "" && index($0, want) == 0) next
      if (match($0, /[0-9A-F-]{36}/)) { print substr($0, RSTART, RLENGTH); exit }
    }'`

if [ -z "$SIM" ]; then
  echo "No matching iPhone simulator${WANTED:+ for \"$WANTED\"}." >&2
  echo "Try: xcrun simctl list devices available" >&2
  exit 1
fi
echo "=== simulator $SIM ==="

xcrun simctl boot "$SIM" 2>/dev/null || true
xcrun simctl bootstatus "$SIM" -b

DERIVED=build-sim

xcodebuild -project ECLHello.xcodeproj \
           -scheme ECLHello \
           -configuration Debug \
           -destination "id=$SIM" \
           -derivedDataPath "$DERIVED" \
           build

APP="$DERIVED/Build/Products/Debug-iphonesimulator/ECLHello.app"

xcrun simctl terminate "$SIM" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl install "$SIM" "$APP"
xcrun simctl launch "$SIM" "$BUNDLE_ID"

open -a Simulator
