#!/bin/bash
# Builds build/Joule.app. Usage: scripts/bundle.sh [--install]
# --install copies it to /Applications and launches it from there.
set -e
cd "$(dirname "$0")/.."

# SwiftPM from Command Line Tools lacks the SwiftUI macro plugins; use Xcode's toolchain.
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
swift build -c release --product JouleApp

APP=build/Joule.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/JouleApp "$APP/Contents/MacOS/Joule"
cp Resources/Info.plist "$APP/Contents/Info.plist"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"

IDENTITY=$(security find-identity -v -p codesigning | grep -o '"Apple Development[^"]*"' | head -1 | tr -d '"')
codesign --force --options runtime --sign "${IDENTITY:--}" "$APP"
echo "Built $APP (signed with ${IDENTITY:-ad-hoc})"

if [ "${1:-}" = "--install" ]; then
    pkill -x Joule || true
    sleep 0.5
    rm -rf /Applications/Joule.app
    cp -R "$APP" /Applications/Joule.app
    open /Applications/Joule.app
    echo "Installed and launched /Applications/Joule.app"
fi
