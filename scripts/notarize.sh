#!/bin/zsh
# Archives Dict, exports it signed with the Developer ID certificate, has
# Apple notarize it, staples the result, and zips it, so it opens on any
# Mac. Prints the zip's path as the last line.
#
# Needs fastlane/.env (gitignored) with an App Store Connect API key:
#   ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH (path to the .p8)
set -euo pipefail
cd "$(dirname "$0")/.."

OUT=build/notarized
TEAM=ZPU7B69KH3

[[ -f fastlane/.env ]] || { echo "Missing fastlane/.env with ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_PATH." >&2; exit 1; }
set -a; source fastlane/.env; set +a
KEY="${ASC_KEY_PATH/#\~/$HOME}"
[[ "$KEY" = /* ]] || KEY="$PWD/fastlane/$KEY"
[[ -f "$KEY" ]] || { echo "Can't find the API key at $KEY." >&2; exit 1; }

rm -rf "$OUT" && mkdir -p "$OUT"

# Exporting for Developer ID signs every piece of the app, Sparkle's
# helpers included, with the hardened runtime and without the debugging
# entitlement, which is what notarization needs.
echo "Archiving" >&2
xcodebuild -project Dict-app.xcodeproj -scheme Dict-app -configuration Release -derivedDataPath build \
    -destination 'platform=macOS' -archivePath "$OUT/Dict.xcarchive" archive > "$OUT/archive.log" 2>&1 \
    || { grep -E "error:" "$OUT/archive.log" >&2; echo "Archive failed. See $OUT/archive.log" >&2; exit 1; }
cat > "$OUT/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>developer-id</string>
    <key>teamID</key><string>$TEAM</string>
    <key>signingStyle</key><string>automatic</string>
</dict>
</plist>
PLIST
echo "Signing with Developer ID" >&2
xcodebuild -exportArchive -archivePath "$OUT/Dict.xcarchive" -exportPath "$OUT/export" \
    -exportOptionsPlist "$OUT/ExportOptions.plist" -allowProvisioningUpdates > "$OUT/export.log" 2>&1 \
    || { grep -E "error:" "$OUT/export.log" >&2; echo "Export failed. See $OUT/export.log" >&2; exit 1; }
APP="$OUT/export/Dict.app"
codesign --verify --deep --strict "$APP"

echo "Sending to Apple for notarization (a few minutes)" >&2
ditto -c -k --keepParent "$APP" "$OUT/upload.zip"
RESULT=$(xcrun notarytool submit "$OUT/upload.zip" --key "$KEY" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID" --wait)
rm "$OUT/upload.zip"
if ! grep -q "status: Accepted" <<< "$RESULT"; then
    echo "$RESULT" >&2
    ID=$(grep -m1 "id:" <<< "$RESULT" | awk '{print $2}')
    [[ -n "$ID" ]] && xcrun notarytool log "$ID" --key "$KEY" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID" >&2
    exit 1
fi

xcrun stapler staple -q "$APP"
spctl --assess --type execute "$APP"

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$APP/Contents/Info.plist")
ZIP="$OUT/Dict-$VERSION-$BUILD.zip"
ditto -c -k --keepParent "$APP" "$ZIP"
echo "Notarized $VERSION build $BUILD" >&2
echo "$ZIP"
