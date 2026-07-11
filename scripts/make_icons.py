#!/usr/bin/env python3
"""Generate Neon Stack app icons as PNGs with no third-party deps.

Draws a dark rounded background with three offset neon blocks (matching the
game's look) at several sizes used by the web app manifest and iOS home screen.
"""
import os
import struct
import zlib
import math

OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "icons")


def hsl_to_rgb(h, s, l):
    c = (1 - abs(2 * l - 1)) * s
    x = c * (1 - abs((h / 60) % 2 - 1))
    m = l - c / 2
    if h < 60:   r, g, b = c, x, 0
    elif h < 120: r, g, b = x, c, 0
    elif h < 180: r, g, b = 0, c, x
    elif h < 240: r, g, b = 0, x, c
    elif h < 300: r, g, b = x, 0, c
    else:         r, g, b = c, 0, x
    return int((r + m) * 255), int((g + m) * 255), int((b + m) * 255)


def blend(dst, src, a):
    return tuple(int(d * (1 - a) + s * a) for d, s in zip(dst, src))


def make_icon(size, maskable=False):
    px = [[(10, 10, 26) for _ in range(size)] for _ in range(size)]

    # Background: vertical gradient + rounded corners (unless maskable -> full bleed)
    radius = 0 if maskable else int(size * 0.22)
    pad = 0
    for y in range(size):
        t = y / size
        top = (18, 16, 48)
        bot = (7, 6, 22)
        row = tuple(int(top[i] * (1 - t) + bot[i] * t) for i in range(3))
        for x in range(size):
            # rounded-corner mask
            if radius:
                cx = min(x, size - 1 - x)
                cy = min(y, size - 1 - y)
                if cx < radius and cy < radius:
                    dx = radius - cx
                    dy = radius - cy
                    if dx * dx + dy * dy > radius * radius:
                        continue
            px[y][x] = row

    # A soft glow center
    for y in range(size):
        for x in range(size):
            dx = (x - size / 2) / (size * 0.6)
            dy = (y - size * 0.42) / (size * 0.6)
            d = dx * dx + dy * dy
            if d < 1:
                g = (1 - d) * 0.18
                px[y][x] = blend(px[y][x], (60, 50, 130), g)

    # Three stacked blocks, each offset, neon hues
    blocks = [
        (0.16, 0.60, 0.66, 200),   # x-frac, w-frac, y-frac, hue
        (0.26, 0.50, 0.44, 265),
        (0.20, 0.44, 0.24, 320),
    ]
    bh = size * 0.15
    br = max(2, int(size * 0.035))
    for xf, wf, yf, hue in blocks:
        bx = int(size * xf)
        bw = int(size * wf)
        by = int(size * yf)
        top = hsl_to_rgb(hue, 0.85, 0.66)
        bottom = hsl_to_rgb(hue, 0.80, 0.48)
        for y in range(by, min(size, int(by + bh))):
            ty = (y - by) / bh
            col = tuple(int(top[i] * (1 - ty) + bottom[i] * ty) for i in range(3))
            for x in range(bx, min(size, bx + bw)):
                # rounded block corners
                cx = min(x - bx, (bx + bw - 1) - x)
                cy = min(y - by, int(by + bh - 1) - y)
                if cx < br and cy < br:
                    dx = br - cx
                    dy = br - cy
                    if dx * dx + dy * dy > br * br:
                        continue
                # subtle glow bleed at edges
                px[y][x] = col
                # top highlight
                if ty < 0.32:
                    px[y][x] = blend(px[y][x], (255, 255, 255), 0.18 * (1 - ty / 0.32))

    return px


def write_png(path, px):
    size = len(px)
    raw = bytearray()
    for row in px:
        raw.append(0)  # filter type 0
        for (r, g, b) in row:
            raw += bytes((r, g, b))
    compressed = zlib.compress(bytes(raw), 9)

    def chunk(tag, data):
        c = struct.pack(">I", len(data)) + tag + data
        c += struct.pack(">I", zlib.crc32(tag + data) & 0xffffffff)
        return c

    sig = b"\x89PNG\r\n\x1a\n"
    ihdr = struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0)  # 8-bit RGB
    with open(path, "wb") as f:
        f.write(sig)
        f.write(chunk(b"IHDR", ihdr))
        f.write(chunk(b"IDAT", compressed))
        f.write(chunk(b"IEND", b""))


def main():
    os.makedirs(OUT, exist_ok=True)
    for size, name in [(180, "icon-180.png"), (192, "icon-192.png"), (512, "icon-512.png")]:
        write_png(os.path.join(OUT, name), make_icon(size))
        print("wrote", name)
    write_png(os.path.join(OUT, "icon-512-maskable.png"), make_icon(512, maskable=True))
    print("wrote icon-512-maskable.png")


if __name__ == "__main__":
    main()
