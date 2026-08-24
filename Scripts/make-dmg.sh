#!/bin/bash
# Packages the already-built app into a drag-to-install DMG.
# Run Scripts/build-app.sh first (or Scripts/release.sh, which builds too).
#
# Usage: Scripts/make-dmg.sh <version, e.g. 1.5.0>
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
    echo "Usage: Scripts/make-dmg.sh <version, e.g. 1.5.0>"
    exit 1
fi

APP_NAME="potatoken hub"
APP_BUNDLE=".build/$APP_NAME.app"
DIST_DIR="dist"
# No spaces — GitHub Release assets mangle them (spaces become dots).
DMG_PATH="$DIST_DIR/potatoken-hub-$VERSION-macOS-arm64.dmg"
STAGING="$DIST_DIR/dmg-staging"

if [ ! -d "$APP_BUNDLE" ]; then
    echo "$APP_BUNDLE not found — run Scripts/build-app.sh first"
    exit 1
fi

echo "Staging DMG contents..."
rm -rf "$STAGING" "$DMG_PATH"
mkdir -p "$STAGING"
cp -R "$APP_BUNDLE" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

echo "Building DMG..."
mkdir -p "$DIST_DIR"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -ov -format UDZO "$DMG_PATH"

rm -rf "$STAGING"
echo "Done: $DMG_PATH"
