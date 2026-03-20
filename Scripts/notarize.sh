#!/bin/bash
# ClipFeed Notarization Script
# Usage: ./Scripts/notarize.sh <version>
# Example: ./Scripts/notarize.sh 1.0.3
#
# Prerequisites:
#   - xcrun notarytool store-credentials "ClipFeed-Notarize" \
#       --apple-id "your@email.com" \
#       --team-id "49DPFSUDS9" \
#       --password "xxxx-xxxx-xxxx-xxxx"  # App-specific password

set -euo pipefail

VERSION="${1:?Usage: $0 <version>}"
APP_NAME="ClipFeed"
BUNDLE_ID="jp.c-c-meguchan.clipfeed"
TEAM_ID="49DPFSUDS9"
KEYCHAIN_PROFILE="ClipFeed-Notarize"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ARTIFACTS_DIR="${PROJECT_DIR}/ReleaseArtifacts/${APP_NAME}-${VERSION}"
ARCHIVE_PATH="${ARTIFACTS_DIR}/${APP_NAME}.xcarchive"
EXPORT_PATH="${ARTIFACTS_DIR}/export"
APP_PATH="${EXPORT_PATH}/${APP_NAME}.app"
DMG_PATH="${ARTIFACTS_DIR}/${APP_NAME}-${VERSION}.dmg"

mkdir -p "${ARTIFACTS_DIR}"

echo "==> Building archive..."
xcodebuild archive \
  -project "${PROJECT_DIR}/ClipboardHistory.xcodeproj" \
  -scheme "ClipboardHistory" \
  -configuration Release \
  -archivePath "${ARCHIVE_PATH}" \
  DEVELOPMENT_TEAM="${TEAM_ID}" \
  CODE_SIGN_IDENTITY="Developer ID Application" \
  CODE_SIGN_STYLE=Automatic

echo "==> Exporting app..."
cat > "${ARTIFACTS_DIR}/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>${TEAM_ID}</string>
    <key>signingStyle</key>
    <string>automatic</string>
</dict>
</plist>
EOF

xcodebuild -exportArchive \
  -archivePath "${ARCHIVE_PATH}" \
  -exportPath "${EXPORT_PATH}" \
  -exportOptionsPlist "${ARTIFACTS_DIR}/ExportOptions.plist"

echo "==> Creating DMG..."
hdiutil create \
  -volname "${APP_NAME}" \
  -srcfolder "${APP_PATH}" \
  -ov \
  -format UDZO \
  "${DMG_PATH}"

echo "==> Signing DMG..."
codesign --sign "Developer ID Application: $(security find-identity -v -p codesigning | grep 'Developer ID Application' | head -1 | sed 's/.*"\(.*\)"/\1/')" \
  --timestamp \
  "${DMG_PATH}"

echo "==> Submitting for notarization..."
xcrun notarytool submit "${DMG_PATH}" \
  --keychain-profile "${KEYCHAIN_PROFILE}" \
  --wait

echo "==> Stapling notarization ticket..."
xcrun stapler staple "${DMG_PATH}"

echo "==> Verifying..."
spctl -a -vvv -t open --context context:primary-signature "${DMG_PATH}"

echo ""
echo "✓ Done! Notarized DMG: ${DMG_PATH}"
