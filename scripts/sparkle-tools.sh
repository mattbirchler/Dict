#!/bin/zsh
# Fetches Sparkle's command line tools (generate_keys, sign_update,
# generate_appcast) into vendor/sparkle. Keep SPARKLE_VERSION in step with
# the Sparkle package pinned in Dict-app.xcodeproj.
set -euo pipefail
cd "$(dirname "$0")/.."
SPARKLE_VERSION=2.9.1
DIR=vendor/sparkle
[[ -x "$DIR/bin/sign_update" && "$(cat $DIR/VERSION 2>/dev/null)" == "$SPARKLE_VERSION" ]] && exit 0
rm -rf "$DIR" && mkdir -p "$DIR"
curl -fsSL "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz" | tar -xJ -C "$DIR" bin
echo "$SPARKLE_VERSION" > "$DIR/VERSION"
echo "Sparkle tools $SPARKLE_VERSION are in $DIR/bin"
