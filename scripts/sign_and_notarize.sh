#!/usr/bin/env bash
set -euo pipefail

APP_NAME="MD-design-macOS"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
VERSION="$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")"
APP_DIR="$DIST_DIR/$APP_NAME-v$VERSION.app"
ZIP_PATH="$DIST_DIR/$APP_NAME-v$VERSION.zip"

: "${DEVELOPER_ID_APPLICATION:?Set DEVELOPER_ID_APPLICATION, for example: Developer ID Application: Name (TEAMID)}"
: "${APPLE_ID:?Set APPLE_ID to the Apple ID used for notarization}"
: "${TEAM_ID:?Set TEAM_ID to your Apple Developer Team ID}"
: "${APP_SPECIFIC_PASSWORD:?Set APP_SPECIFIC_PASSWORD to an app-specific password}"

"$ROOT_DIR/scripts/package_app.sh" release

codesign --force --deep --options runtime --timestamp --sign "$DEVELOPER_ID_APPLICATION" "$APP_DIR"
codesign --verify --deep --strict --verbose=2 "$APP_DIR"

rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP_DIR" "$ZIP_PATH"

xcrun notarytool submit "$ZIP_PATH" \
    --apple-id "$APPLE_ID" \
    --team-id "$TEAM_ID" \
    --password "$APP_SPECIFIC_PASSWORD" \
    --wait

xcrun stapler staple "$APP_DIR"
spctl --assess --type execute --verbose "$APP_DIR"

echo "Signed and notarized: $APP_DIR"
