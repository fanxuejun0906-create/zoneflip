#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/ZoneFlip.app"
BIN="$APP/Contents/MacOS/ZoneFlip"
DEPLOYMENT_TARGET="11.0"

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

# Build a universal binary so the same download runs natively on Apple Silicon
# and Intel Macs.
for ARCH in arm64 x86_64; do
  mkdir -p "$ROOT/.build/out/$ARCH"
  swiftc -O -target "$ARCH-apple-macos$DEPLOYMENT_TARGET" \
    -module-cache-path "$ROOT/.build/ModuleCache" \
    -framework Cocoa \
    -o "$ROOT/.build/out/$ARCH/ZoneFlip" "$ROOT"/Sources/*.swift
done

/usr/bin/lipo -create \
  "$ROOT/.build/out/arm64/ZoneFlip" \
  "$ROOT/.build/out/x86_64/ZoneFlip" \
  -output "$BIN"

/usr/bin/codesign --force --sign - "$APP" >/dev/null 2>&1 || true

echo "Built $APP ($(/usr/bin/lipo -archs "$BIN"))"
