#!/bin/bash
# FileLister - Production Build Script

# This script attempts to build the FileLister app in Release configuration.
# Note: For public distribution, you should still use Xcode's Product > Archive
# to handle Apple Notarization and Developer ID signing correctly.

APP_NAME="FileLister"
BUILD_DIR="./build"
DIST_DIR="./Dist"

echo "🚀 Starting Production Build for $APP_NAME..."

# 1. Cleanup
rm -rf "$BUILD_DIR"
mkdir -p "$DIST_DIR"

# 2. Build via xcodebuild
echo "📦 Compiling project..."
xcodebuild -scheme "$APP_NAME" \
           -configuration Release \
           -derivedDataPath "$BUILD_DIR" \
           build | grep -A 5 "error:"

# 3. Locate and Copy the .app
SOURCE_APP="$BUILD_DIR/Build/Products/Release/$APP_NAME.app"

if [ -d "$SOURCE_APP" ]; then
    echo "✅ Build Successful!"
    echo "📂 Copying app to $DIST_DIR..."
    cp -R "$SOURCE_APP" "$DIST_DIR/"
    
    # Create a ZIP for easy GitHub upload
    cd "$DIST_DIR"
    zip -r "$APP_NAME-macOS.zip" "$APP_NAME.app"
    cd ..
    
    echo "--------------------------------------------------"
    echo "🎉 READY FOR RELEASE!"
    echo "Location: $DIST_DIR/$APP_NAME.app"
    echo "Zip for GitHub: $DIST_DIR/$APP_NAME-macOS.zip"
    echo "--------------------------------------------------"
else
    echo "❌ Error: Could not find the built .app. Please check if the Scheme name is '$APP_NAME'."
fi
