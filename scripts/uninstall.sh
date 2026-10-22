#!/bin/bash
# Remove ZoneFlip, its helper, its sudoers rule and its login item.
set -euo pipefail

pkill -f "ZoneFlip.app/Contents/MacOS/ZoneFlip" 2>/dev/null || true
sleep 1

osascript -e 'do shell script "/bin/rm -rf /Applications/ZoneFlip.app /usr/local/libexec/zoneflip-tz /etc/sudoers.d/zoneflip; /bin/echo removed" with administrator privileges'

rm -f "$HOME/Library/LaunchAgents/com.jennie.zoneflip.plist"
rm -rf "$HOME/Library/Application Support/ZoneFlip"

echo "ZoneFlip removed. Your current system time zone was left unchanged."
