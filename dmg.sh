#!/bin/zsh
# Build Drive Radio and package it as dist/DriveRadio.dmg (drag to Applications).
set -euo pipefail
cd "$(dirname "$0")"

xcodegen generate --quiet
xcodebuild -project DriveRadio.xcodeproj -scheme DriveRadio -configuration Release \
  -derivedDataPath build -destination 'platform=macOS,arch=arm64' -destination 'platform=macOS,arch=x86_64' \
  ONLY_ACTIVE_ARCH=NO build -quiet

stage=build/dmg
rm -rf "$stage" dist/DriveRadio.dmg
mkdir -p "$stage" dist
cp -R "build/Build/Products/Release/Drive Radio.app" "$stage/"
ln -s /Applications "$stage/Applications"
hdiutil create -volname "Drive Radio" -srcfolder "$stage" -format UDZO -ov dist/DriveRadio.dmg -quiet
codesign --sign "Apple Development" dist/DriveRadio.dmg
echo "Built dist/DriveRadio.dmg"
