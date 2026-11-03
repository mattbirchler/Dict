"""Draws the disk image background: the HUD's near-black panel with a lit
dot-matrix arrow from the app to the Applications folder. Pure Pillow-free
PNG writing so it runs on a stock macOS Python."""
import math
import struct
import sys
import zlib

W, H = 600, 380
SCALE = 2  # retina
TOP = (0.10, 0.08, 0.09)
BOTTOM = (0.05, 0.04, 0.05)
LOW = (1.0, 0.42, 0.16)
HIGH = (1.0, 0.24, 0.50)
UNLIT = 0.10


def lerp(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


def dots():
    """Dot centers (x, y, lit) for a right-pointing arrow of LEDs on a
    faint grid. Unlit dots come first so lit ones draw over them."""
    out = []
    pitch = 14
    cx, cy = 300, 185
    lit = set()
    for col in range(-6, 3):            # shaft, 3 rows
        for row in (-1, 0, 1):
            lit.add((col, row))
    for i, half in enumerate((2, 1, 0)):  # head: 5, 3, 1 dots
        for row in range(-half, half + 1):
            lit.add((3 + i, row))
    for col in range(-10, 11):
        for row in range(-3, 4):
            if (col, row) not in lit:
                out.append((cx + col * pitch, cy + row * pitch, False))
    for (col, row) in sorted(lit):
        out.append((cx + col * pitch, cy + row * pitch, True))
    return out


def render():
    w, h = W * SCALE, H * SCALE
    px = bytearray(w * h * 3)
    for y in range(h):
        t = y / (h - 1)
        base = lerp(TOP, BOTTOM, t)
        for x in range(w):
            i = (y * w + x) * 3
            px[i] = int(base[0] * 255)
            px[i + 1] = int(base[1] * 255)
            px[i + 2] = int(base[2] * 255)
    lit = []
    for (dx, dy, on) in dots():
        r = 4.6 * SCALE
        color = lerp(LOW, HIGH, max(0.0, min(1.0, (dy - 143) / 84))) if on else None
        for y in range(int((dy - r - 8) * SCALE), int((dy + r + 8) * SCALE)):
            for x in range(int((dx - r - 8) * SCALE), int((dx + r + 8) * SCALE)):
                if not (0 <= x < w and 0 <= y < h):
                    continue
                d = math.hypot(x - dx * SCALE, y - dy * SCALE)
                i = (y * w + x) * 3
                if on:
                    glow = max(0.0, 1 - d / (r * 2.6)) ** 2 * 0.55
                    core = 1.0 if d <= r else max(0.0, 1 - (d - r) / (1.2 * SCALE))
                    a = min(1.0, core + glow)
                    for c in range(3):
                        px[i + c] = int(px[i + c] + (color[c] * 255 - px[i + c]) * a)
                elif d <= r:
                    for c in range(3):
                        px[i + c] = int(px[i + c] + (LOW[c] * 255 * UNLIT + 20 - px[i + c]) * 0.9)
    # a faint rim line along the top, like the HUD
    for x in range(w):
        i = x * 3
        for c in range(3):
            px[i + c] = int(px[i + c] + ((LOW[c] * 255) - px[i + c]) * 0.35)
    return w, h, bytes(px)


def write_png(path, w, h, rgb):
    raw = b"".join(b"\x00" + rgb[y * w * 3:(y + 1) * w * 3] for y in range(h))

    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    ihdr = struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)
    # pHYs marks it as 144 dpi so Finder shows it at 600x380 points.
    phys = struct.pack(">IIB", 5669, 5669, 1)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"pHYs", phys)
                + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


if __name__ == "__main__":
    w, h, rgb = render()
    write_png(sys.argv[1], w, h, rgb)
