# Composes the press images in docs/press from panel renders and window
# snapshots. Usage: see scripts/press-images.sh.
import sys, os, math
from PIL import Image, ImageDraw, ImageFilter, ImageFont
RAW, OUT, FONTS, ICON = sys.argv[1:5]
W, H = 2400, 1500

def backdrop(w=W, h=H, warm=(255, 98, 46), pink=(255, 61, 128)):
    img = Image.new("RGB", (w, h), (13, 11, 18))
    glow = Image.new("RGB", (w, h), (0, 0, 0))
    d = ImageDraw.Draw(glow)
    for (cx, cy, r, c, a) in [(w * .18, h * 1.0, w * .55, warm, .55), (w * .92, h * .05, w * .45, pink, .35), (w * .5, h * .55, w * .45, (60, 40, 90), .45)]:
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=tuple(int(v * a) for v in c))
    glow = glow.filter(ImageFilter.GaussianBlur(w * .12))
    img = Image.blend(img, Image.composite(glow, img, Image.new("L", (w, h), 255)), 1.0)
    img = Image.fromarray if False else img
    base = Image.new("RGB", (w, h), (13, 11, 18))
    img = Image.eval(img, lambda v: v)  # keep
    out = Image.new("RGB", (w, h))
    out.paste(base)
    out = Image.blend(out, img, 1.0)
    # Faint LED dot grid, the matrix motif.
    dots = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    dd = ImageDraw.Draw(dots)
    pitch = 36
    for y in range(pitch // 2, h, pitch):
        for x in range(pitch // 2, w, pitch):
            dd.ellipse([x - 2.2, y - 2.2, x + 2.2, y + 2.2], fill=(255, 255, 255, 9))
    out = out.convert("RGBA")
    out.alpha_composite(dots)
    return out

def shadowed(win, radius=60, offset=40, opacity=150):
    pad = radius * 3
    canvas = Image.new("RGBA", (win.width + pad * 2, win.height + pad * 2), (0, 0, 0, 0))
    a = win.split()[3].point(lambda v: opacity if v > 8 else 0)
    sh = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    shadow_layer = Image.new("RGBA", win.size, (0, 0, 0, 255)); shadow_layer.putalpha(a)
    sh.paste(shadow_layer, (pad, pad + offset), shadow_layer)
    sh = sh.filter(ImageFilter.GaussianBlur(radius))
    canvas.alpha_composite(sh)
    canvas.alpha_composite(win, (pad, pad))
    return canvas, pad

def place_center(bg, im, cx, cy):
    bg.alpha_composite(im, (int(cx - im.width / 2), int(cy - im.height / 2)))

def load(name): return Image.open(os.path.join(RAW, name)).convert("RGBA")
def scale(im, f): return im.resize((round(im.width * f), round(im.height * f)), Image.LANCZOS)
def font(weight, size): return ImageFont.truetype(os.path.join(FONTS, f"ChakraPetch-{weight}.ttf"), size)
def label(bg, text, xy, size=30, fill=(255, 176, 102), anchor="mm", weight="SemiBold", track=6):
    d = ImageDraw.Draw(bg); f = font(weight, size)
    # Manual tracking.
    widths = [d.textlength(ch, font=f) + track for ch in text]
    total = sum(widths) - track
    x, y = xy
    if anchor == "mm": x -= total / 2
    for ch, wd in zip(text, widths):
        d.text((x, y), ch, font=f, fill=fill, anchor="lm"); x += wd

def save(im, name): im.convert("RGB").save(os.path.join(OUT, name), optimize=True)

# 1 Hero: the pill and the hands-free panel.
bg = backdrop()
hf = scale(load("hud-handsfree.png"), 0.78)
pill = scale(load("hud-recording.png"), 0.78)
place_center(bg, pill, W / 2 - (hf.width - pill.width) / 2, H * .34)
place_center(bg, hf, W / 2, H * .63)
save(bg, "dict-hero.png")

# 2 Flow: hold, let go, done.
bg = backdrop()
items = [("hud-recording.png", "HOLD THE KEY AND TALK"), ("hud-processing.png", "LET GO"), ("hud-done.png", "IT'S TYPED FOR YOU")]
ys = [H * .25, H * .5, H * .75]
for (f, t), y in zip(items, ys):
    im = scale(load(f), 0.8)
    place_center(bg, im, W * .64, y)
    label(bg, t, (W * .07, y), size=40, anchor="lm")
save(bg, "dict-flow.png")

# 3 Schemes: five pills.
bg = backdrop()
names = [("hud-recording.png", "EMBER"), ("hud-recording-phosphor.png", "PHOSPHOR"), ("hud-recording-glacier.png", "GLACIER"), ("hud-recording-ultraviolet.png", "ULTRAVIOLET"), ("hud-recording-graphite.png", "GRAPHITE")]
for i, (f, t) in enumerate(names):
    im = scale(load(f), 0.5)
    y = H * (.13 + i * .185)
    place_center(bg, im, W * .6, y)
    label(bg, t, (W * .12, y), size=38, anchor="lm", fill=(241, 236, 240))
save(bg, "dict-color-schemes.png")

# 4-6 Windows.
for f, name, sc in [("win-general.png", "dict-settings.png", 0.98), ("win-history.png", "dict-history.png", 0.98), ("onb-tryit.png", "dict-onboarding.png", 1.0)]:
    bg = backdrop()
    win = load(f)
    f2 = min(sc, (H * .84) / win.height, (W * .8) / win.width)
    win = scale(win, f2)
    sh, pad = shadowed(win)
    place_center(bg, sh, W / 2, H / 2 + 10)
    save(bg, name)

# 7 Card: icon, name, tagline.
bg = backdrop()
icon = Image.open(ICON).convert("RGBA").resize((560, 560), Image.LANCZOS)
sh, pad = shadowed(icon, radius=40, offset=24, opacity=120)
place_center(bg, sh, W * .3, H / 2)
label(bg, "DICT", (W * .5, H * .40), size=200, anchor="lm", fill=(255, 244, 236), weight="Bold", track=30)
label(bg, "PRIVATE DICTATION FOR THE MAC", (W * .505, H * .56), size=46, anchor="lm", fill=(255, 176, 102), track=8)
label(bg, "FREE  ·  OPEN SOURCE  ·  100% ON-DEVICE", (W * .505, H * .64), size=34, anchor="lm", fill=(190, 180, 196), weight="Medium", track=6)
save(bg, "dict-card.png")
print("ok")
