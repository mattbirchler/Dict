#!/bin/zsh
# Writes a screenshot of the HUD in every mode and both appearances into $1,
# using the Debug build's --preview-hud --snapshot mode, each trimmed and
# composited on a dark or light backdrop. Developer aid.
set -euo pipefail
OUT=${1:?output folder}
APP=${2:-build/Build/Products/Debug/Dict.app}
mkdir -p "$OUT"
for appearance in dark light; do
  for mode in recording handsfree processing done failed; do
    raw="$OUT/raw-$appearance-$mode.png"
    "$APP/Contents/MacOS/Dict" --preview-hud "$mode" --appearance "$appearance" --snapshot "$raw"
    magick "$raw" -trim +repage "$raw" 2>/dev/null
    read w h <<< "$(identify -format '%w %h' "$raw" 2>/dev/null)"
    if [[ $appearance == dark ]]; then bg="gradient:#15172a-#2a1f3d"; else bg="gradient:#dbe6fa-#f6e8dc"; fi
    magick -size "$((w + 120))x$((h + 80))" "$bg" "$raw" -gravity center -composite "$OUT/$appearance-$mode.png" 2>/dev/null
    rm -f "$raw"
  done
done
echo "Shots in $OUT"
