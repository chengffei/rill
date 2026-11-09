#!/bin/bash
# Release build, then dist/Rill-<version>.dmg, .zip and .sha256, plus fixed-name
# Rill.zip and Rill.sha256 for install.sh. Apple silicon only: the SMC keys Rill
# reads, and their byte order, are those of Apple chips.
set -e
cd "$(dirname "$0")/.."

scripts/bundle.sh

APP=build/Rill.app
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
mkdir -p dist
DMG="dist/Rill-$VERSION.dmg"
ZIP="dist/Rill-$VERSION.zip"
STAGE=build/dmg
rm -rf "$STAGE" "$DMG" "$ZIP"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Rill $VERSION" -srcfolder "$STAGE" -format UDZO -imagekey zlib-level=9 -quiet "$DMG"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
cp "$ZIP" dist/Rill.zip
rm -rf "$STAGE"
(cd dist && shasum -a 256 "Rill-$VERSION.dmg" "Rill-$VERSION.zip" Rill.zip | tee "Rill-$VERSION.sha256" > Rill.sha256)
