#!/bin/bash
#
# One-line installer for the latest ZoneFlip release.
#
#   curl -fsSL https://raw.githubusercontent.com/fanxuejun0906-create/zoneflip/main/scripts/remote-install.sh | bash
#
# Downloads the universal build from GitHub Releases, installs it into
# /Applications (or ~/Applications when /Applications is not writable),
# removes the quarantine flag and launches it.
#
set -euo pipefail

REPO="fanxuejun0906-create/zoneflip"
URL="https://github.com/$REPO/releases/latest/download/ZoneFlip.zip"
DEST="/Applications/ZoneFlip.app"

say() { printf '%s\n' "$*"; }

command -v curl >/dev/null 2>&1 || { say "需要 curl，请先安装命令行工具。"; exit 1; }

TMP="$(mktemp -d /tmp/zoneflip.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

say "下载最新版 ZoneFlip…"
curl -fL --retry 3 --connect-timeout 15 "$URL" -o "$TMP/ZoneFlip.zip"

/usr/bin/ditto -x -k "$TMP/ZoneFlip.zip" "$TMP"
APP="$TMP/ZoneFlip.app"
[ -d "$APP" ] || { say "压缩包内容异常，请到 https://github.com/$REPO/releases 手动下载。"; exit 1; }

/usr/bin/pkill -f "ZoneFlip.app/Contents/MacOS/ZoneFlip" 2>/dev/null || true
sleep 1

if [ -w /Applications ]; then
  /bin/rm -rf "$DEST"
  /usr/bin/ditto "$APP" "$DEST"
elif /usr/bin/osascript -e "do shell script \"/bin/rm -rf '$DEST' && /usr/bin/ditto '$APP' '$DEST'\" with administrator privileges" >/dev/null 2>&1; then
  :
else
  DEST="$HOME/Applications/ZoneFlip.app"
  /bin/mkdir -p "$HOME/Applications"
  /bin/rm -rf "$DEST"
  /usr/bin/ditto "$APP" "$DEST"
fi

/usr/bin/xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true
/usr/bin/open "$DEST"

say "已安装到 $DEST 并启动。"
say "提示：点菜单栏图标 →「安装免密助手」输一次密码，之后切换时区不再弹框。"
