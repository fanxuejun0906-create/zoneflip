#!/bin/bash
# Build ZoneFlip and install it to /Applications.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/ZoneFlip.app"
DEST="/Applications/ZoneFlip.app"

bash "$ROOT/scripts/build.sh"

pkill -f "ZoneFlip.app/Contents/MacOS/ZoneFlip" 2>/dev/null || true
sleep 1

if [ -w /Applications ]; then
  rm -rf "$DEST"
  ditto "$APP" "$DEST"
else
  # The privileged shell may not be able to read the working copy (sandbox,
  # external volume, ...), so stage the bundle somewhere world-readable first.
  STAGE="$(mktemp -d /tmp/zoneflip-install.XXXXXX)"
  ditto "$APP" "$STAGE/ZoneFlip.app"
  chmod -R a+rX "$STAGE"
  osascript -e "do shell script \"/bin/rm -rf '$DEST' && /usr/bin/ditto '$STAGE/ZoneFlip.app' '$DEST' && /usr/sbin/chown -R root:wheel '$DEST'\" with administrator privileges"
  rm -rf "$STAGE"
fi

open "$DEST"
echo "Installed and launched $DEST"
