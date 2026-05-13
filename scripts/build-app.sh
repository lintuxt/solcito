#!/usr/bin/env bash
#
# Packages the SolcitoApp SwiftPM executable into a real .app bundle so it
# behaves like a normal macOS app (Dock icon, Cmd-Tab, double-click launch).
# Defaults to a release build; pass `debug` as the first arg for a debug one.
#
# Output: .build/Solcito.app
#
# After building:
#   open .build/Solcito.app          # launch
#   cp -R .build/Solcito.app /Applications/   # install
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${1:-release}"

cd "$REPO"
echo "→ swift build -c $CONFIG --product Solcito"
swift build -c "$CONFIG" --product Solcito

BIN_DIR="$(swift build -c "$CONFIG" --product Solcito --show-bin-path)"
BIN="$BIN_DIR/Solcito"
[ -f "$BIN" ] || { echo "✗ Binary not found at $BIN"; exit 1; }

APP="$REPO/.build/Solcito.app"
echo "→ Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Solcito"
cp "$REPO/apple/Info.plist" "$APP/Contents/Info.plist"
chmod +x "$APP/Contents/MacOS/Solcito"

echo "✓ Built $APP"
echo "  Launch: open '$APP'"
