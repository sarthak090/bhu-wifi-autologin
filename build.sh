#!/bin/zsh
# Builds "BHU WiFi.app" (universal: Apple Silicon + Intel).
#   ./build.sh          build, install into /Applications (or ~/Applications) and launch
#   ./build.sh dist     build and zip into dist/BHU-WiFi.zip for a GitHub release
set -euo pipefail

cd "${0:A:h}"
MODE="${1:-install}"
VERSION="${VERSION:-$(cat VERSION)}"
BUNDLE_ID="io.github.sarthak090.bhu-wifi"
APP="build/BHU WiFi.app"

rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "==> Compiling $VERSION"
for arch in arm64 x86_64; do
  swiftc -O -swift-version 5 -target "$arch-apple-macos13.0" -o "build/BHUWiFi-$arch" Sources/*.swift
done
lipo -create -output "$APP/Contents/MacOS/BHUWiFi" build/BHUWiFi-arm64 build/BHUWiFi-x86_64

echo "==> Icon"
swift scripts/make-icon.swift build/AppIcon.iconset
iconutil -c icns -o "$APP/Contents/Resources/AppIcon.icns" build/AppIcon.iconset

LOCATION_REASON="macOS only shares the Wi-Fi network name with apps that have Location access. BHU WiFi uses it to stay idle on every network except the campus Wi-Fi. Your location is never read or stored."

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleName</key><string>BHU WiFi</string>
  <key>CFBundleDisplayName</key><string>BHU WiFi</string>
  <key>CFBundleExecutable</key><string>BHUWiFi</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHumanReadableCopyright</key><string>MIT License</string>
  <key>NSLocationUsageDescription</key><string>$LOCATION_REASON</string>
  <key>NSLocationWhenInUseUsageDescription</key><string>$LOCATION_REASON</string>
</dict>
</plist>
PLIST
plutil -lint "$APP/Contents/Info.plist"

# Ad-hoc signature (required to run on Apple Silicon). Not notarized.
codesign --force --sign - "$APP"

if [[ "$MODE" == "dist" ]]; then
  mkdir -p dist
  rm -f dist/BHU-WiFi.zip
  ditto -c -k --keepParent "$APP" dist/BHU-WiFi.zip
  echo "==> dist/BHU-WiFi.zip"
  exit 0
fi

DEST="/Applications"
[[ -w "$DEST" ]] || DEST="$HOME/Applications"
mkdir -p "$DEST"
pkill -x BHUWiFi 2>/dev/null && sleep 1 || true
rm -rf "$DEST/BHU WiFi.app"
ditto "$APP" "$DEST/BHU WiFi.app"
open "$DEST/BHU WiFi.app"
echo "==> Installed and launched $DEST/BHU WiFi.app"
