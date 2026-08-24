#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

# The Swift target still builds a binary called TokenGauge; APP_NAME is what
# the user sees in Finder, the menu bar, and the about panel.
PRODUCT_NAME="TokenGauge"
APP_NAME="potatoken hub"
VERSION="1.8.0"
BUILD_NUMBER="8"

# Deliberately unchanged across the rename. A bundle identifier is the app's
# stable identity, and repointing it would strand the preferences (saved panel
# position) and the login-item registration that are filed under it.
BUNDLE_ID="com.local.tokengauge"

BUILD_DIR=".build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"

echo "Building release binary..."
swift build -c release

echo "Assembling app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

BIN_PATH="$(swift build -c release --show-bin-path)"
cp "$BIN_PATH/$PRODUCT_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Rebuild the icon from its source art whenever that art is newer, so the
# .icns can't quietly fall behind the PNG it was made from.
ICON_SOURCE="Resources/AppIcon-source.png"
ICON_ICNS="Resources/AppIcon.icns"
if [ -f "$ICON_SOURCE" ] && { [ ! -f "$ICON_ICNS" ] || [ "$ICON_SOURCE" -nt "$ICON_ICNS" ]; }; then
    echo "Generating icon..."
    ICONSET="$BUILD_DIR/AppIcon.iconset"
    rm -rf "$ICONSET"
    mkdir -p "$ICONSET"
    for spec in "16 icon_16x16" "32 icon_16x16@2x" "32 icon_32x32" "64 icon_32x32@2x" \
                "128 icon_128x128" "256 icon_128x128@2x" "256 icon_256x256" "512 icon_256x256@2x" \
                "512 icon_512x512" "1024 icon_512x512@2x"; do
        px="${spec% *}"
        name="${spec#* }"
        sips -s format png -z "$px" "$px" "$ICON_SOURCE" --out "$ICONSET/$name.png" >/dev/null
    done
    iconutil -c icns "$ICONSET" -o "$ICON_ICNS"
    rm -rf "$ICONSET"
fi

if [ -f "$ICON_ICNS" ]; then
    cp "$ICON_ICNS" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi

cat > "$APP_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_NUMBER</string>
    <key>LSUIElement</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHumanReadableCopyright</key>
    <string>bmminky · MIT License</string>
</dict>
</plist>
PLIST

echo "Signing (ad-hoc)..."
codesign --force --deep --sign - "$APP_BUNDLE"

echo "Verifying..."
codesign --verify --verbose "$APP_BUNDLE"

echo "Done: $APP_BUNDLE"
