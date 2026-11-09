#!/bin/bash
# Installs the latest Rill release.
#   curl -fsSL https://raw.githubusercontent.com/chengffei/rill/main/install.sh | bash
#
# Files downloaded with curl carry no quarantine flag, so macOS opens the app without the
# "unidentified developer" prompt. In exchange the script checks what it downloaded:
# the published SHA-256, a valid code signature, and the expected bundle ID and team.
set -euo pipefail

[ "$(uname -m)" = arm64 ] || { echo "error: Rill needs a Mac with Apple silicon" >&2; exit 1; }

REPO="chengffei/rill"
BUNDLE_ID="io.github.chengffei.rill"
TEAM_ID="TWK29JGBQJ"
DEST="${RILL_INSTALL_DIR:-/Applications}"
[ -w "$DEST" ] || DEST="$HOME/Applications"
mkdir -p "$DEST"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# Fixed asset names on the latest release; the GitHub API is rate-limited for anonymous use.
BASE="https://github.com/$REPO/releases/latest/download"
ZIP_NAME="Rill.zip"

echo "==> Downloading the latest Rill"
curl -fsSL "$BASE/$ZIP_NAME" -o "$WORK/$ZIP_NAME"
curl -fsSL "$BASE/Rill.sha256" -o "$WORK/sums"
(cd "$WORK" && grep " $ZIP_NAME\$" sums | shasum -a 256 -c - >/dev/null) \
    || { echo "error: checksum does not match" >&2; exit 1; }

ditto -x -k "$WORK/$ZIP_NAME" "$WORK/unzipped"
APP="$WORK/unzipped/Rill.app"
codesign --verify --deep --strict "$APP" 2>/dev/null || { echo "error: invalid code signature" >&2; exit 1; }
[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")" = "$BUNDLE_ID" ] \
    || { echo "error: unexpected bundle ID" >&2; exit 1; }
codesign -dv "$APP" 2>&1 | grep -q "TeamIdentifier=$TEAM_ID" || { echo "error: unexpected signer" >&2; exit 1; }

pkill -x Rill 2>/dev/null && sleep 1 || true
rm -rf "$DEST/Rill.app"
ditto "$APP" "$DEST/Rill.app"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$DEST/Rill.app/Contents/Info.plist")
echo "==> Installed Rill $VERSION in $DEST"
[ -n "${RILL_NO_OPEN:-}" ] || open "$DEST/Rill.app"
