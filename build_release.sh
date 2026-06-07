#!/bin/bash
# FileLister - Clean & Build
#
# Cleans and builds a fresh Release .app into ./Dist.
# Version numbering, git commit, and GitHub release are handled separately, as needed.

set -euo pipefail

APP_NAME="FileLister"
BUILD_DIR="./build"
DIST_DIR="./Dist"
SOURCE_APP="$BUILD_DIR/Build/Products/Release/$APP_NAME.app"

echo "🛑 Stopping any running instance..."
pkill -f "$APP_NAME.app/Contents/MacOS/$APP_NAME" 2>/dev/null || true

echo "🧹 Cleaning previous build..."
rm -rf "$BUILD_DIR"
mkdir -p "$DIST_DIR"

echo "📦 Building $APP_NAME (Release)..."
xcodebuild -project "$APP_NAME.xcodeproj" \
           -scheme "$APP_NAME" \
           -configuration Release \
           -derivedDataPath "$BUILD_DIR" \
           clean build

if [ ! -d "$SOURCE_APP" ]; then
    echo "❌ Build finished but $SOURCE_APP was not found."
    exit 1
fi

echo "📂 Copying app to $DIST_DIR..."
rm -rf "$DIST_DIR/$APP_NAME.app"
cp -R "$SOURCE_APP" "$DIST_DIR/"

echo "✅ Done: $DIST_DIR/$APP_NAME.app"

echo "🚀 Launching $APP_NAME..."
open "$DIST_DIR/$APP_NAME.app"
