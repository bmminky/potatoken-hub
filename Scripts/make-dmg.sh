#!/bin/bash
# Packages the already-built app into a drag-to-install DMG.
# Run Scripts/build-app.sh first (or Scripts/release.sh, which builds too).
#
# Usage: Scripts/make-dmg.sh
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="potatoken hub"
APP_BUNDLE=".build/$APP_NAME.app"
DIST_DIR="dist"
DMG_PATH="$DIST_DIR/$APP_NAME.dmg"
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
