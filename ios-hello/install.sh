#!/bin/sh
#
# Build ECLHello, sign it, and install it on a connected iPhone.
#
#   ./install.sh              # first available device
#   ./install.sh <device-id>  # from `xcrun devicectl list devices`
#
# Requires ../ecl-iOS, i.e. run ../build.sh first.
#
# If signing fails, open ECLHello.xcodeproj in Xcode once and press Run:
# Xcode repairs the certificate chain and creates the provisioning profile,
# after which this script works on its own.

set -e

cd "`dirname "$0"`"

if [ ! -d ../ecl-iOS/lib ]; then
  echo "../ecl-iOS not found -- run ../build.sh first." >&2
  exit 1
fi

DEVICE="$1"
if [ -z "$DEVICE" ]; then
  # Device names contain spaces, so pick the field that looks like a UUID.
  # "unavailable" contains "available", hence the second test.
  DEVICE=`xcrun devicectl list devices 2>/dev/null | awk '
      $0 ~ /available/ && $0 !~ /unavailable/ {
        for (i = 1; i <= NF; i++)
          if ($i ~ /^[0-9A-F]{8}-[0-9A-F]{4}-/) { print $i; exit }
      }'`
fi
if [ -z "$DEVICE" ]; then
  echo "No available device. Plug in your iPhone, unlock it, and trust this Mac." >&2
  exit 1
fi
# aot.o is linked in by the Xcode project but Xcode knows nothing about how it
# is produced, so it would happily link a stale one. build-aot.sh is a no-op
# when it is already current.
./build-aot.sh

echo "=== device $DEVICE ==="

DERIVED=build

# -allowProvisioningUpdates lets Xcode register the device and create the
# App ID and provisioning profile on the developer account as needed.
xcodebuild -project ECLHello.xcodeproj \
           -scheme ECLHello \
           -configuration Debug \
           -destination "id=$DEVICE" \
           -derivedDataPath "$DERIVED" \
           -allowProvisioningUpdates \
           build

APP="$DERIVED/Build/Products/Debug-iphoneos/ECLHello.app"

echo "=== installing $APP ==="
xcrun devicectl device install app --device "$DEVICE" "$APP"

echo
echo "Installed. Launch \"ECL Hello\" from the home screen."
echo "If iOS refuses to open it, trust the developer under"
echo "Settings > General > VPN & Device Management."
