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
xcodebuild -project "FileLister/FileLister.xcodeproj" \
           -scheme "$APP_NAME" \
           -configuration Release \
           -derivedDataPath "$BUILD_DIR" \
           build | grep -A 5 "error:"

# 3. Locate and Copy the .app
SOURCE_APP="$BUILD_DIR/Build/Products/Release/$APP_NAME.app"

if [ -d "$SOURCE_APP" ]; then
    echo "✅ Build Successful!"
    echo "📂 Copying app and resources to $DIST_DIR..."
    cp -R "$SOURCE_APP" "$DIST_DIR/"
    cp "FileLister/FileLister/FileLister/Resources/screenshot.png" "$DIST_DIR/$APP_NAME.app/Contents/Resources/" 2>/dev/null
    
    # Create a ZIP for easy GitHub upload
    cd "$DIST_DIR"
    zip -r "filelister.zip" "$APP_NAME.app"
    cd ..
    
    echo "--------------------------------------------------"
    echo "🎉 READY FOR RELEASE!"
    echo "Location: $DIST_DIR/$APP_NAME.app"
    echo "Zip for GitHub: $DIST_DIR/filelister.zip"
    echo "--------------------------------------------------"

    # --- NEW: Automated GitHub Release Upload (Robust Version) ---
    if command -v /opt/homebrew/bin/gh &> /dev/null; then
        echo "🚀 Preparing GitHub Release..."
        
        LATEST_TAG="v1.2.0"
        echo "🚀 Creating/Updating release $LATEST_TAG..."
        /opt/homebrew/bin/gh release create "$LATEST_TAG" --title "FileLister $LATEST_TAG" --notes "Release v1.2.0 - Features: New Secure Email-Bound Licensing System." 2>/dev/null

        echo "📦 Uploading filelister.zip to release $LATEST_TAG..."
        /opt/homebrew/bin/gh release upload "$LATEST_TAG" "$DIST_DIR/filelister.zip" --clobber
        
        if [ $? -eq 0 ]; then
            echo "✅ Upload Successful to $LATEST_TAG!"
        else
            echo "⚠️  Upload failed. Ensure you are logged in using 'gh auth login' and have repo permissions."
        fi
    else
        echo "ℹ️  GitHub CLI (gh) not found at /opt/homebrew/bin/gh. Skipping automated upload."
    fi
else
    echo "❌ Error: Could not find the built .app. Please check if the Scheme name is '$APP_NAME'."
fi
