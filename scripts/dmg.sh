#!/bin/zsh
# Wraps a notarized Dict.app in a disk image with a drag-to-Applications
# background, signs the image, has Apple notarize it and staples it.
# Usage: scripts/dmg.sh path/to/Dict.app  (prints the dmg path last)
#
# dmgbuild (pip) lays out the Finder window without scripting Finder; it
# lives in a venv under vendor/ (gitignored) that this script creates.
set -euo pipefail
cd "$(dirname "$0")/.."
APP=${1:?path to Dict.app}
[[ -d "$APP" ]] || { echo "No app at $APP" >&2; exit 1; }

VENV=vendor/dmgbuild
if [[ ! -x "$VENV/bin/dmgbuild" ]]; then
    echo "Installing dmgbuild into $VENV" >&2
    python3 -m venv "$VENV"
    "$VENV/bin/pip" -q install dmgbuild
fi

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$APP/Contents/Info.plist")
OUT="$(dirname "$APP")/../Dict-$VERSION-$BUILD.dmg"
OUT=$(python3 -c "import os,sys; print(os.path.normpath(sys.argv[1]))" "$OUT")
rm -f "$OUT"

python3 scripts/dmg/background.py scripts/dmg/background.png
APP_PATH="$APP" "$VENV/bin/dmgbuild" -s scripts/dmg/settings.py "Dict $VERSION" "$OUT" >&2

# SIGN=1 (set by notarize.sh) signs and notarizes the image; a local
# `make dmg` of an unsigned build skips that.
if [[ "${SIGN:-0}" == 1 && -f fastlane/.env ]]; then
    set -a; source fastlane/.env; set +a
    KEY="${ASC_KEY_PATH/#\~/$HOME}"
    [[ "$KEY" = /* ]] || KEY="$PWD/fastlane/$KEY"
    IDENTITY=$(security find-identity -v -p codesigning | grep -m1 "Developer ID Application" | sed -E 's/.*"(.*)"/\1/')
    [[ -n "$IDENTITY" ]] || { echo "No Developer ID Application identity in the keychain." >&2; exit 1; }
    codesign --sign "$IDENTITY" --timestamp "$OUT"
    echo "Notarizing the disk image" >&2
    RESULT=$(xcrun notarytool submit "$OUT" --key "$KEY" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID" --wait)
    grep -q "status: Accepted" <<< "$RESULT" || { echo "$RESULT" >&2; exit 1; }
    xcrun stapler staple -q "$OUT"
else
    echo "Disk image left unsigned (fine for a local look)." >&2
fi
echo "$OUT"
