#!/bin/bash
set -e
cd "$(dirname "$0")"

APP_NAME="BO3 Launcher"
NOTARY_PROFILE="notarytool-profile"
TEAM_ID="J497DX6ZF8"
SIGN_ID="Developer ID Application: Max Awad ($TEAM_ID)"

command -v xcodegen >/dev/null 2>&1 || { echo "Install xcodegen: brew install xcodegen"; exit 1; }

echo "==> Regenerating Xcode project..."
xcodegen generate --quiet

echo "==> Archiving Release..."
rm -rf build
xcodebuild archive \
  -project BO3Launcher.xcodeproj \
  -scheme BO3Launcher \
  -configuration Release \
  -archivePath build/BO3Launcher.xcarchive \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$SIGN_ID" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  PROVISIONING_PROFILE_SPECIFIER="" \
  ENABLE_HARDENED_RUNTIME=YES \
  OTHER_CODE_SIGN_FLAGS="--timestamp" \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  2>&1 | tail -10

ARCHIVE="build/BO3Launcher.xcarchive"
if [ ! -d "$ARCHIVE" ]; then
  echo "❌ Archive failed"
  exit 1
fi

APP_PATH="$ARCHIVE/Products/Applications/$APP_NAME.app"
if [ ! -d "$APP_PATH" ]; then
  echo "❌ App not found in archive"
  ls -R "$ARCHIVE/Products/" 2>/dev/null
  exit 1
fi

echo "==> Re-signing with secure timestamp..."
codesign --force --deep --timestamp \
  --sign "$SIGN_ID" \
  --options runtime \
  "$APP_PATH"

echo "==> Verifying signature..."
codesign -dv --verbose=2 "$APP_PATH" 2>&1 | grep -E "Authority|TeamIdentifier|Signature|flags"

echo "==> Checking entitlements..."
codesign -d --entitlements - "$APP_PATH" 2>&1 | head -20

echo "==> Creating ZIP for notarization..."
ZIP_PATH="build/$APP_NAME.zip"
rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

echo "==> Submitting for notarization..."
xcrun notarytool submit "$ZIP_PATH" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait

echo "==> Stapling notarization ticket..."
xcrun stapler staple "$APP_PATH"

echo "==> Creating final distributable ZIP..."
DIST_ZIP="build/BO3-Launcher.zip"
rm -f "$DIST_ZIP"
ditto -c -k --keepParent "$APP_PATH" "$DIST_ZIP"

echo ""
echo "✅ Done! Distributable: $DIST_ZIP"
echo "   Upload this to maxawad.com for download."
