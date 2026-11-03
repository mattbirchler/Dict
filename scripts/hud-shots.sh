#!/bin/zsh
# Writes a screenshot of the HUD in every mode and both appearances into $1,
# using the Debug build's --preview-hud --snapshot mode, each trimmed and
# composited on a dark or light backdrop. Developer aid.
set -euo pipefail
OUT=${1:?output folder}
APP=${2:-build/Build/Products/Debug/Dict.app}
SCHEME=${SCHEME:-ember}
mkdir -p "$OUT"
for appearance in dark light; do
  for mode in recording handsfree processing done failed; do
    raw="$OUT/raw-$appearance-$mode.png"
    "$APP/Contents/MacOS/Dict" --preview-hud "$mode" --appearance "$appearance" --scheme "$SCHEME" --snapshot "$raw"
    # The capture is the transparent panel alone; flatten it on a backdrop
    # so the pill's glow reads the way it does over a desktop.
    if [[ $appearance == dark ]]; then bg="#1f1b33"; else bg="#dfe6f5"; fi
    magick "$raw" -background "$bg" -flatten -trim +repage -bordercolor "$bg" -border 40x24 "$OUT/$appearance-$mode.png" 2>/dev/null
    rm -f "$raw"
  done
done
echo "Shots in $OUT"
