#!/bin/zsh
# Rebuilds docs/press: renders the panel at 4x, snapshots the windows with
# sample data, and frames everything on the Dict backdrop. Needs a Debug
# build (make build) and Pillow.
set -euo pipefail
APP=${APP:-build/Build/Products/Debug/Dict.app}
RAW=$(mktemp -d)
BIN="$APP/Contents/MacOS/Dict"
for m in recording handsfree processing done; do "$BIN" --render-hud $m --scale 4 --out "$RAW/hud-$m.png"; done
for s in phosphor glacier ultraviolet graphite; do "$BIN" --render-hud recording --scheme $s --scale 4 --out "$RAW/hud-recording-$s.png"; done
"$BIN" --preview-window general --sample-stats --snapshot "$RAW/win-general.png"
"$BIN" --preview-window history --sample-stats --snapshot "$RAW/win-history.png"
"$BIN" --preview-onboarding tryit --snapshot "$RAW/onb-tryit.png"
"/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool" dict-icon.icon \
  --export-image --output-file "$RAW/icon-1024.png" --platform macOS --rendition Default --width 512 --height 512 --scale 2
python3 scripts/press-images.py "$RAW" docs/press Dict-app/Fonts "$RAW/icon-1024.png"
rm -rf "$RAW"
