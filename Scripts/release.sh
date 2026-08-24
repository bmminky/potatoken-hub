#!/bin/bash
# Cuts a new release: bumps the version, builds, installs, verifies, then
# commits, tags, and pushes. Run from a clean working tree with everything
# you want in the release already committed except the version bump itself.
#
# Usage: Scripts/release.sh 1.5.0 "One-line summary of what changed"
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-}"
SUMMARY="${2:-}"
if [ -z "$VERSION" ] || [ -z "$SUMMARY" ]; then
    echo "Usage: Scripts/release.sh <version, e.g. 1.5.0> <summary>"
    exit 1
fi
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Version must look like 1.5.0"
    exit 1
fi
TAG="v$VERSION"
if git rev-parse "$TAG" >/dev/null 2>&1; then
    echo "Tag $TAG already exists"
    exit 1
fi

if [ -n "$(git status --porcelain)" ]; then
    echo "Working tree isn't clean — commit or stash first:"
    git status --short
    exit 1
fi

BUILD_SCRIPT="Scripts/build-app.sh"
CURRENT_BUILD=$(sed -n 's/^BUILD_NUMBER="\(.*\)"$/\1/p' "$BUILD_SCRIPT")
NEXT_BUILD=$((CURRENT_BUILD + 1))

echo "Bumping to $VERSION (build $NEXT_BUILD)..."
sed -i '' "s/^VERSION=\".*\"$/VERSION=\"$VERSION\"/" "$BUILD_SCRIPT"
sed -i '' "s/^BUILD_NUMBER=\".*\"$/BUILD_NUMBER=\"$NEXT_BUILD\"/" "$BUILD_SCRIPT"

echo "Running tests..."
swift test

echo "Stopping any running instance..."
pkill -9 -f "potatoken hub" 2>/dev/null || true

"$BUILD_SCRIPT"

APP_NAME="potatoken hub"
echo "Installing to /Applications..."
rm -rf "/Applications/$APP_NAME.app"
ditto ".build/$APP_NAME.app" "/Applications/$APP_NAME.app"

echo "Verifying installed binary matches the build..."
INSTALLED_HASH=$(md5 -q "/Applications/$APP_NAME.app/Contents/MacOS/$APP_NAME")
BUILT_HASH=$(md5 -q ".build/$APP_NAME.app/Contents/MacOS/$APP_NAME")
if [ "$INSTALLED_HASH" != "$BUILT_HASH" ]; then
    echo "Hash mismatch after install — aborting release"
    exit 1
fi
echo "Hashes match: $INSTALLED_HASH"

open "/Applications/$APP_NAME.app"
sleep 2
if ! pgrep -f "$APP_NAME" >/dev/null; then
    echo "App did not start after install — aborting release"
    exit 1
fi
echo "App is running."

echo "Committing and tagging..."
git add "$BUILD_SCRIPT"
git commit -m "Release $TAG: $SUMMARY"
git tag -a "$TAG" -m "$SUMMARY"

echo "Pushing..."
git push origin main
git push origin "$TAG"

echo "Released $TAG."
