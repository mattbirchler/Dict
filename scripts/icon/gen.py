# Regenerates dict-icon.icon (the Menu Bar Grid app icon) and .bench/icon.png.
# Usage: python3 scripts/icon/gen.py [path/to/dict-icon.icon]
# The icon is the status item's 5x4 grid at Dock size, lit in Ember on the
# HUD's panel, with baked bloom. Needs Pillow (pip3 install pillow).
import json, os, sys
from PIL import Image, ImageDraw, ImageFilter

OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "dict-icon.icon")
ASSETS = os.path.join(OUT, "Assets")
os.makedirs(ASSETS, exist_ok=True)

LOW, HIGH = (255, 107, 41), (255, 61, 128)       # HUDColorScheme.ember low/high
COLS, ROWS = 5, 4
LEVELS = [0.25, 0.75, 0.5, 1.0, 0.5]             # MenuBarIcon.idleLevels
CANVAS = 1024
PITCH = 150                                      # 3.6 pt in the menu bar
R = PITCH * 2.4 / 3.6 / 2                        # 2.4 pt dots, same ratio

def mix(a, b, t): return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))
def hexc(c): return "#%02X%02X%02X" % c

dots = []   # (x, y, lit, row)
for i in range(COLS):
    x = CANVAS / 2 + (i - 2) * PITCH
    lit_rows = round(LEVELS[i] * ROWS)
    for j in range(ROWS):
        y = CANVAS / 2 + (1.5 - j) * PITCH
        dots.append((x, y, j < lit_rows, j))

def svg(body, defs=""):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{CANVAS}" height="{CANVAS}" '
            f'viewBox="0 0 {CANVAS} {CANVAS}">{defs}{body}</svg>\n')

# Unlit dots: the menu bar draws these at 22% of the lit color.
unlit = "".join(f'<circle cx="{x:g}" cy="{y:g}" r="{R:g}"/>' for x, y, lit, j in dots if not lit)
with open(os.path.join(ASSETS, "unlit.svg"), "w") as f:
    f.write(svg(f'<g fill="{hexc(LOW)}" fill-opacity="0.22">{unlit}</g>'))

# Lit dots: Ember low at the base to high at the top, each with a hot core.
defs, lit = [], []
for j in range(ROWS):
    c = mix(LOW, HIGH, j / (ROWS - 1))
    defs.append(f'<radialGradient id="r{j}" cx=".42" cy=".4" r=".62">'
                f'<stop offset="0" stop-color="{hexc(mix(c, (255,255,255), 0.5))}"/>'
                f'<stop offset=".48" stop-color="{hexc(c)}"/>'
                f'<stop offset="1" stop-color="{hexc(mix(c, (0,0,0), 0.08))}"/></radialGradient>')
for x, y, is_lit, j in dots:
    if is_lit:
        lit.append(f'<circle cx="{x:g}" cy="{y:g}" r="{R:g}" fill="url(#r{j})"/>')
with open(os.path.join(ASSETS, "lit.svg"), "w") as f:
    f.write(svg("".join(lit), "<defs>" + "".join(defs) + "</defs>"))

# Bloom: blurred copies of the lit dots, a wide soft halo and a tight one,
# baked to a PNG at 2x so it stays smooth in the 1024 pt export.
SCALE = 2
size = CANVAS * SCALE
glow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
for j in range(ROWS):
    mask = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(mask)
    for x, y, is_lit, row in dots:
        if is_lit and row == j:
            d.ellipse([(x - R) * SCALE, (y - R) * SCALE, (x + R) * SCALE, (y + R) * SCALE], fill=255)
    c = mix(LOW, HIGH, j / (ROWS - 1))
    for sigma, opacity in ((52, 0.6), (15, 0.9)):
        a = mask.filter(ImageFilter.GaussianBlur(sigma * SCALE)).point(lambda v: int(v * opacity))
        layer = Image.new("RGBA", (size, size), c + (0,))
        layer.putalpha(a)
        glow = Image.alpha_composite(glow, layer)
glow.save(os.path.join(ASSETS, "bloom.png"))

for stale in ("wave.svg",):
    p = os.path.join(ASSETS, stale)
    if os.path.exists(p): os.remove(p)

def group(name, image, scale=None, shadow=0.0):
    layer = {"image-name": image, "name": name}
    if scale: layer["position"] = {"scale": scale, "translation-in-points": [0, 0]}
    return {"layers": [layer],
            "shadow": {"kind": "neutral", "opacity": shadow},
            "specular": False,
            "translucency": {"enabled": False, "value": 0}}

icon = {
    # The HUD's panel: pillTop rgb(0.10,0.08,0.09) over pillBottom rgb(0.05,0.04,0.05).
    "fill": {"automatic-gradient": "srgb:0.09000,0.07000,0.08000,1.00000"},
    "groups": [
        group("lit", "lit.svg"),
        group("unlit", "unlit.svg"),
        group("bloom", "bloom.png", scale=1 / SCALE),
    ],
    "supported-platforms": {"circles": ["watchOS"], "squares": "shared"},
}
with open(os.path.join(OUT, "icon.json"), "w") as f:
    json.dump(icon, f, indent=2)
    f.write("\n")
print("wrote", sorted(os.listdir(ASSETS)))

# The Workbench sidebar icon is the Default rendition at 256 px.
ICTOOL = "/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool"
if os.path.exists(ICTOOL):
    import subprocess
    bench = os.path.join(os.path.dirname(OUT), ".bench", "icon.png")
    os.makedirs(os.path.dirname(bench), exist_ok=True)
    subprocess.run([ICTOOL, OUT, "--export-image", "--output-file", bench, "--platform", "macOS",
                    "--rendition", "Default", "--width", "256", "--height", "256", "--scale", "1"],
                   check=True, capture_output=True)
    print("wrote", bench)
