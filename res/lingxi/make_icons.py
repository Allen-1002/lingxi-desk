#!/usr/bin/env python3
"""Generate Nimbo app icons from one drawing.

Concept: a soft white cloud (Nimbo, 云朵) on the teal-to-indigo tile.

Run from the repo root:  python3 res/lingxi/make_icons.py
Needs Pillow. Writes every icon the Android, macOS, Windows and Flutter builds use.
"""
import math
import os

from PIL import Image, ImageDraw

C1 = (20, 184, 166)   # teal  #14B8A6
C2 = (79, 70, 229)    # indigo #4F46E5
WHITE = (255, 255, 255, 255)
SS = 4  # supersampling


def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def gradient(size):
    """Diagonal gradient, top-left teal to bottom-right indigo."""
    small = Image.new("RGB", (256, 256))
    px = small.load()
    for y in range(256):
        for x in range(256):
            px[x, y] = lerp(C1, C2, (x + y) / 510)
    return small.resize((size, size), Image.BICUBIC)


def bezier(p0, p1, p2, n=96):
    pts = []
    for i in range(n + 1):
        t = i / n
        x = (1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * p1[0] + t * t * p2[0]
        y = (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * p1[1] + t * t * p2[1]
        pts.append((x, y))
    return pts


# Glyph in unit coordinates (0..1 box): a cloud made of three puffs on a
# rounded base.
DY = 0.03
PUFFS = [((0.33, 0.56 + DY), 0.17), ((0.54, 0.44 + DY), 0.22), ((0.72, 0.58 + DY), 0.15)]
BASE = ((0.16, 0.55 + DY, 0.87, 0.73 + DY), 0.09)


def draw_glyph(img, box, color=WHITE):
    """Draw the glyph into img inside box=(x0, y0, size)."""
    x0, y0, s = box
    d = ImageDraw.Draw(img)
    for (cx, cy), r in PUFFS:
        cx, cy, r = x0 + cx * s, y0 + cy * s, r * s
        d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=color)
    (bx0, by0, bx1, by1), br = BASE
    d.rounded_rectangle(
        (x0 + bx0 * s, y0 + by0 * s, x0 + bx1 * s, y0 + by1 * s), br * s, fill=color)


def rounded_mask(size, radius):
    m = Image.new("L", (size, size), 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, size - 1, size - 1), radius, fill=255)
    return m


def full_icon(size, pad=0.0, radius=0.225, glyph_scale=0.8):
    """Gradient rounded square with white glyph. pad = transparent margin ratio."""
    S = size * SS
    out = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    inner = int(round(S * (1 - 2 * pad)))
    off = (S - inner) // 2
    tile = gradient(inner).convert("RGBA")
    g = int(inner * glyph_scale)
    draw_glyph(tile, ((inner - g) / 2, (inner - g) / 2 + inner * 0.02, g))
    out.paste(tile, (off, off), rounded_mask(inner, int(inner * radius)))
    return out.resize((size, size), Image.LANCZOS)


def glyph_only(size, scale, color=WHITE):
    S = size * SS
    out = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    g = S * scale
    draw_glyph(out, ((S - g) / 2, (S - g) / 2, g), color)
    return out.resize((size, size), Image.LANCZOS)


def save(img, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path)
    print("wrote", path)


def svg():
    g = 0.8
    o = (1 - g) / 2 * 100
    puffs = "".join(
        f'<circle cx="{cx * 100:.1f}" cy="{cy * 100:.1f}" r="{r * 100:.1f}"/>'
        for (cx, cy), r in PUFFS)
    (bx0, by0, bx1, by1), br = BASE
    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
  <defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1">
    <stop offset="0" stop-color="#14B8A6"/><stop offset="1" stop-color="#4F46E5"/>
  </linearGradient></defs>
  <rect width="100" height="100" rx="22.5" fill="url(#g)"/>
  <g transform="translate({o:.1f} {o + 2:.1f}) scale({g})" fill="#fff">
    {puffs}<rect x="{bx0 * 100:.1f}" y="{by0 * 100:.1f}" width="{(bx1 - bx0) * 100:.1f}" height="{(by1 - by0) * 100:.1f}" rx="{br * 100:.1f}"/>
  </g>
</svg>
'''


def main():
    res = "res"
    android = "flutter/android/app/src/main/res"
    save(full_icon(1024), f"{res}/icon.png")
    # macOS icons: rounded tile with Apple's standard ~10% margin.
    save(full_icon(1024, pad=0.098, radius=0.2237), f"{res}/mac-icon.png")
    for n, s in (("32x32", 32), ("64x64", 64), ("128x128", 128), ("128x128@2x", 256)):
        save(full_icon(s), f"{res}/{n}.png")
    ico = full_icon(256)
    ico.save(f"{res}/icon.ico", sizes=[(16, 16), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
    print("wrote", f"{res}/icon.ico")
    full_icon(64).save(f"{res}/tray-icon.ico", sizes=[(16, 16), (32, 32)])
    print("wrote", f"{res}/tray-icon.ico")
    # macOS menu-bar template images (black glyph, system tints them).
    save(glyph_only(60, 0.95, (0, 0, 0, 255)), f"{res}/mac-tray-dark-x2.png")
    save(glyph_only(48, 0.95, (0, 0, 0, 255)), f"{res}/mac-tray-light-x2.png")

    dens = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}
    for d, k in dens.items():
        base = f"{android}/mipmap-{d}"
        save(full_icon(int(48 * k), radius=0.225), f"{base}/ic_launcher.png")
        save(full_icon(int(48 * k), radius=0.5), f"{base}/ic_launcher_round.png")
        # Adaptive foreground: 108dp canvas, glyph inside the 66dp safe zone.
        save(glyph_only(int(108 * k), 0.50), f"{base}/ic_launcher_foreground.png")
        save(glyph_only(int(24 * k), 0.95), f"{base}/ic_stat_logo.png")

    with open("flutter/assets/icon.svg", "w") as f:
        f.write(svg())
    with open(f"{res}/lingxi/icon.svg", "w") as f:
        f.write(svg())
    print("wrote svg")


if __name__ == "__main__":
    main()
