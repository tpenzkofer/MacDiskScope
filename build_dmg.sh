#!/bin/bash
set -e

APP_NAME="MacDiskScope"
SCHEME="MacDiskScope"
PROJECT="MacDirStat.xcodeproj"
BUILD_DIR="build"
DMG_NAME="${APP_NAME}.dmg"
VOLUME_NAME="${APP_NAME}"

echo "=== Building ${APP_NAME} Release ==="

# Clean and build Release
xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
    -configuration Release \
    -derivedDataPath "${BUILD_DIR}/DerivedData" \
    clean build \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_ALLOWED=YES

# Find the built app
APP_PATH="${BUILD_DIR}/DerivedData/Build/Products/Release/${APP_NAME}.app"

if [ ! -d "$APP_PATH" ]; then
    echo "ERROR: ${APP_PATH} not found"
    exit 1
fi

echo "=== App built at ${APP_PATH} ==="
echo "=== Creating DMG ==="

# Create a temporary directory for the DMG contents
DMG_TEMP="${BUILD_DIR}/dmg_temp"
rm -rf "$DMG_TEMP"
mkdir -p "$DMG_TEMP"

# Copy the app
cp -R "$APP_PATH" "$DMG_TEMP/"

# Create a symlink to /Applications
ln -s /Applications "$DMG_TEMP/Applications"

# Remove any existing DMG
rm -f "${BUILD_DIR}/${DMG_NAME}"

# Create the DMG
hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$DMG_TEMP" \
    -ov \
    -format UDZO \
    -imagekey zlib-level=9 \
    "${BUILD_DIR}/${DMG_NAME}"

# Clean up
rm -rf "$DMG_TEMP"

DMG_SIZE=$(du -h "${BUILD_DIR}/${DMG_NAME}" | cut -f1)
echo ""
echo "=== Done! ==="
echo "DMG: ${BUILD_DIR}/${DMG_NAME} (${DMG_SIZE})"
echo ""
echo "To install: Open the DMG and drag MacDiskScope to Applications."
