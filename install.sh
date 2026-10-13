#!/bin/bash
# Installs the latest BHU WiFi release:
#   curl -fsSL https://raw.githubusercontent.com/sarthak090/bhu-wifi-autologin/main/install.sh | bash
set -euo pipefail

REPO="sarthak090/bhu-wifi-autologin"
URL="https://github.com/$REPO/releases/latest/download/BHU-WiFi.zip"

DEST="/Applications"
[ -w "$DEST" ] || DEST="$HOME/Applications"
mkdir -p "$DEST"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "Downloading BHU WiFi…"
curl -fsSL "$URL" -o "$TMP/BHU-WiFi.zip"
ditto -x -k "$TMP/BHU-WiFi.zip" "$TMP"

pkill -x BHUWiFi 2>/dev/null && sleep 1 || true
rm -rf "$DEST/BHU WiFi.app"
ditto "$TMP/BHU WiFi.app" "$DEST/BHU WiFi.app"
# The app is not notarized; clear the download flag so Gatekeeper doesn't block it.
xattr -dr com.apple.quarantine "$DEST/BHU WiFi.app" 2>/dev/null || true

open "$DEST/BHU WiFi.app"
echo "Installed $DEST/BHU WiFi.app — look for the graduation cap in your menu bar."
