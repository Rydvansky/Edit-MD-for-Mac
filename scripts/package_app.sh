#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Edit MD for Mac"
EXECUTABLE_NAME="EditMDForMac"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
VERSION="$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")"
ARCHIVE_BASENAME="$APP_NAME-v$VERSION${APP_VARIANT:+-$APP_VARIANT}"
APP_BUNDLE_NAME="$ARCHIVE_BASENAME.app"
APP_DIR="$DIST_DIR/$APP_BUNDLE_NAME"
ZIP_PATH="$DIST_DIR/$ARCHIVE_BASENAME.zip"
DMG_PATH="$DIST_DIR/$ARCHIVE_BASENAME.dmg"
DMG_STAGE="$DIST_DIR/dmg-stage"
BUILD_CONFIGURATION="${1:-release}"
SWIFT_BUILD_PATH="${SWIFT_BUILD_PATH:-$ROOT_DIR/.build}"

cd "$ROOT_DIR"

if [ ! -f "$ROOT_DIR/Resources/AppIcon.icns" ]; then
    swift "$ROOT_DIR/scripts/make_icon.swift" "$ROOT_DIR/Resources/AppIcon.iconset"
    iconutil -c icns "$ROOT_DIR/Resources/AppIcon.iconset" -o "$ROOT_DIR/Resources/AppIcon.icns"
fi

swift build --scratch-path "$SWIFT_BUILD_PATH" -c "$BUILD_CONFIGURATION"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$SWIFT_BUILD_PATH/$BUILD_CONFIGURATION/$EXECUTABLE_NAME" "$APP_DIR/Contents/MacOS/$EXECUTABLE_NAME"
cp "$ROOT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP_DIR/Contents/Info.plist"
if [ -n "${APP_BUNDLE_ID:-}" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $APP_BUNDLE_ID" "$APP_DIR/Contents/Info.plist"
fi
cp "$ROOT_DIR/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
cp "$ROOT_DIR/markdown_demo.md" "$APP_DIR/Contents/Resources/markdown_demo.md"
cp "$ROOT_DIR/THIRD_PARTY_NOTICES.md" "$APP_DIR/Contents/Resources/THIRD_PARTY_NOTICES.md"
mkdir -p "$APP_DIR/Contents/Resources/Webview"
cp "$ROOT_DIR/Resources/Webview/"* "$APP_DIR/Contents/Resources/Webview/"
chmod +x "$APP_DIR/Contents/MacOS/$EXECUTABLE_NAME"

codesign --force --deep --sign - "$APP_DIR" >/dev/null

rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP_DIR" "$ZIP_PATH"

rm -rf "$DMG_STAGE" "$DMG_PATH"
mkdir -p "$DMG_STAGE"
cp -R "$APP_DIR" "$DMG_STAGE/$APP_BUNDLE_NAME"
ln -s /Applications "$DMG_STAGE/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_STAGE" -ov -format UDZO "$DMG_PATH" >/dev/null
rm -rf "$DMG_STAGE"

echo "Packaged: $APP_DIR"
echo "Archive: $ZIP_PATH"
echo "Disk image: $DMG_PATH"
