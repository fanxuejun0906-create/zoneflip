#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/ZoneFlip.app"
BIN="$APP/Contents/MacOS/ZoneFlip"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/helper/zoneflip-tz" "$APP/Contents/Resources/zoneflip-tz"
cp "$ROOT/helper/zoneflip.sudoers" "$APP/Contents/Resources/zoneflip.sudoers"
chmod 0755 "$APP/Contents/Resources/zoneflip-tz"

if [ -f "$ROOT/Resources/AppIcon.icns" ]; then
  cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

mkdir -p "$ROOT/.build/ModuleCache" "$ROOT/.build/tmp"
export TMPDIR="$ROOT/.build/tmp"

swiftc -O -target arm64-apple-macos13.0 \
  -module-cache-path "$ROOT/.build/ModuleCache" \
  -framework Cocoa \
  -o "$BIN" "$ROOT"/Sources/*.swift

/usr/bin/codesign --force --sign - "$APP" >/dev/null 2>&1 || true

echo "Built $APP"
