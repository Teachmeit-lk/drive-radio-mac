#!/bin/zsh
# Build Drive Radio (menu bar app + widget), install it in /Applications and start it.
set -euo pipefail
cd "$(dirname "$0")"

xcodegen generate --quiet
xcodebuild -project DriveRadio.xcodeproj -scheme DriveRadio -configuration Release \
  -derivedDataPath build -destination 'platform=macOS' build -quiet

app="build/Build/Products/Release/Drive Radio.app"
pkill -x "Drive Radio" 2>/dev/null || true
rm -rf "/Applications/Drive Radio.app"
cp -R "$app" /Applications/
# register the widget with the system and start the app
pluginkit -a "/Applications/Drive Radio.app/Contents/PlugIns/DriveRadioWidget.appex" 2>/dev/null || true
open "/Applications/Drive Radio.app"
echo "Installed /Applications/Drive Radio.app"
