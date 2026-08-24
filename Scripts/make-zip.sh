#!/bin/bash
# Zips the already-built app for direct GitHub Release download, alongside
# the DMG from Scripts/make-dmg.sh.
# Run Scripts/build-app.sh first (or Scripts/release.sh, which builds too).
#
# Usage: Scripts/make-zip.sh <version, e.g. 1.5.0>
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
    echo "Usage: Scripts/make-zip.sh <version, e.g. 1.5.0>"
    exit 1
fi

APP_NAME="potatoken hub"
APP_BUNDLE=".build/$APP_NAME.app"
DIST_DIR="dist"
ZIP_PATH="$DIST_DIR/potatoken-hub-$VERSION-macOS-arm64.zip"

if [ ! -d "$APP_BUNDLE" ]; then
    echo "$APP_BUNDLE not found — run Scripts/build-app.sh first"
    exit 1
fi

mkdir -p "$DIST_DIR"
rm -f "$ZIP_PATH"

echo "Zipping..."
ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ZIP_PATH"

echo "Done: $ZIP_PATH"
