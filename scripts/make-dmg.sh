#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

xcodegen generate

APP_NAME="Yanmo"
PROJECT_NAME="Yanmo"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "${PROJECT_NAME}/Info.plist")
BUILD_DIR="build"
DIST_DIR="dist"
DMG_PATH="${DIST_DIR}/${APP_NAME}-${VERSION}.dmg"

rm -rf "$BUILD_DIR" "$DIST_DIR"
mkdir -p "$DIST_DIR"

xcodebuild \
  -project "${PROJECT_NAME}.xcodeproj" \
  -target "$PROJECT_NAME" \
  -configuration Release \
  CONFIGURATION_BUILD_DIR="${PWD}/${BUILD_DIR}/Release" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM="" \
  build

APP_PATH="${BUILD_DIR}/Release/${APP_NAME}.app"

codesign --force --deep --sign - --options runtime "$APP_PATH"
codesign --verify --deep --strict "$APP_PATH"

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP_PATH" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGE" \
  -ov -format UDZO \
  "$DMG_PATH"

echo
echo "DMG written to: $DMG_PATH"
echo "Tell friends: right-click Yanmo.app → Open the first time (unidentified developer warning is expected)."
