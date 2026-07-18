#!/usr/bin/env python3
"""Generate the Time Sheets app icon (1024×1024 RGBA PNG), no third-party deps.

Draws a rounded-rect blue/indigo card with a white clock and a green check
badge — echoing the menu-bar `clock.badge.checkmark` symbol. Run:

    python3 make_icon.py        # writes AppIcon.png next to this script

Then build the .icns on a Mac with ../make_icon.sh (uses sips + iconutil).
"""
import math
import os
import struct
import zlib

SIZE = 1024
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "AppIcon.png")


def clamp(x, lo=0.0, hi=1.0):
    return lo if x < lo else hi if x > hi else x


def lerp(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


def over(dst, src):
    """Alpha-composite src over dst; both are (r,g,b,a) in 0..1."""
    sa = src[3]
    a = sa + dst[3] * (1 - sa)
    if a <= 1e-6:
        return (0.0, 0.0, 0.0, 0.0)
    r = (src[0] * sa + dst[0] * dst[3] * (1 - sa)) / a
    g = (src[1] * sa + dst[1] * dst[3] * (1 - sa)) / a
    b = (src[2] * sa + dst[2] * dst[3] * (1 - sa)) / a
    return (r, g, b, a)


def rounded_rect_sdf(x, y, cx, cy, hw, hh, r):
    """Signed distance to a rounded rect; negative inside."""
    dx = abs(x - cx) - (hw - r)
    dy = abs(y - cy) - (hh - r)
    ox, oy = max(dx, 0.0), max(dy, 0.0)
    outside = math.hypot(ox, oy)
    inside = min(max(dx, dy), 0.0)
    return outside + inside - r


def seg_dist(px, py, ax, ay, bx, by):
    """Distance from point to segment AB."""
    vx, vy = bx - ax, by - ay
    wx, wy = px - ax, py - ay
    denom = vx * vx + vy * vy
    t = 0.0 if denom == 0 else clamp((wx * vx + wy * vy) / denom)
    cx, cy = ax + t * vx, ay + t * vy
    return math.hypot(px - cx, py - cy)


def cov(inside_pixels):
    """1px anti-aliased coverage from an inside-positive distance."""
    return clamp(inside_pixels + 0.5)


# Palette
BG_TOP = (0.31, 0.27, 0.90)     # #4F46E5 indigo
BG_BOT = (0.145, 0.388, 0.922)  # #2563EB blue
WHITE = (1.0, 1.0, 1.0)
GREEN = (0.133, 0.773, 0.369)   # #22C55E

# Geometry
CARD_HW = CARD_HH = 412
CARD_R = 185
CENTER = SIZE / 2
CLK_X, CLK_Y = 466, 462
RING_RC, RING_HT = 232, 27      # ring centre radius / half-thickness
HUB_R = 28
BADGE_X, BADGE_Y, BADGE_R = 712, 712, 150

# Clock hands (a classic 10:10)
MIN_END = (CLK_X + 150 * math.sin(math.radians(60)),
           CLK_Y - 150 * math.cos(math.radians(60)))
HOUR_END = (CLK_X + 108 * math.sin(math.radians(305)),
            CLK_Y - 108 * math.cos(math.radians(305)))

# Check mark points (relative to badge centre)
CHK = [(-62, 4), (-14, 54), (72, -52)]


def pixel(x, y):
    col = (0.0, 0.0, 0.0, 0.0)

    # Card background
    sdf = rounded_rect_sdf(x, y, CENTER, CENTER, CARD_HW, CARD_HH, CARD_R)
    bg_cov = cov(-sdf)
    if bg_cov <= 0:
        return col  # outside the card → transparent
    base = lerp(BG_TOP, BG_BOT, clamp((y - (CENTER - CARD_HH)) / (2 * CARD_HH)))
    col = over(col, (base[0], base[1], base[2], bg_cov))

    # Soft top sheen for depth
    sheen = clamp((CENTER - y) / SIZE) * 0.10
    if sheen > 0:
        col = over(col, (1, 1, 1, sheen * bg_cov))

    d_clk = math.hypot(x - CLK_X, y - CLK_Y)

    # Clock ring
    ring = cov(RING_HT - abs(d_clk - RING_RC))
    if ring > 0:
        col = over(col, (WHITE[0], WHITE[1], WHITE[2], ring * 0.97))

    # Hands + hub
    mh = cov(15 - seg_dist(x, y, CLK_X, CLK_Y, MIN_END[0], MIN_END[1]))
    hh = cov(19 - seg_dist(x, y, CLK_X, CLK_Y, HOUR_END[0], HOUR_END[1]))
    hub = cov(HUB_R - d_clk)
    hand = max(mh, hh, hub)
    if hand > 0:
        col = over(col, (WHITE[0], WHITE[1], WHITE[2], hand * 0.97))

    # Check badge — white separation ring, then green disc, then white check
    d_badge = math.hypot(x - BADGE_X, y - BADGE_Y)
    halo = cov((BADGE_R + 12) - d_badge)
    if halo > 0:
        col = over(col, (WHITE[0], WHITE[1], WHITE[2], halo))
    disc = cov(BADGE_R - d_badge)
    if disc > 0:
        col = over(col, (GREEN[0], GREEN[1], GREEN[2], disc))
        # check mark
        pts = [(BADGE_X + p[0], BADGE_Y + p[1]) for p in CHK]
        dchk = min(seg_dist(x, y, pts[0][0], pts[0][1], pts[1][0], pts[1][1]),
                   seg_dist(x, y, pts[1][0], pts[1][1], pts[2][0], pts[2][1]))
        chk = cov(17 - dchk) * disc
        if chk > 0:
            col = over(col, (WHITE[0], WHITE[1], WHITE[2], chk))

    return col


def main():
    raw = bytearray()
    for y in range(SIZE):
        raw.append(0)  # PNG filter type 0
        for x in range(SIZE):
            r, g, b, a = pixel(x, y)
            raw += bytes((round(r * 255), round(g * 255), round(b * 255), round(a * 255)))

    compressed = zlib.compress(bytes(raw), 9)

    def chunk(tag, data):
        c = struct.pack(">I", len(data)) + tag + data
        return c + struct.pack(">I", zlib.crc32(tag + data) & 0xffffffff)

    ihdr = struct.pack(">IIBBBBB", SIZE, SIZE, 8, 6, 0, 0, 0)  # 8-bit RGBA
    with open(OUT, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", ihdr))
        f.write(chunk(b"IDAT", compressed))
        f.write(chunk(b"IEND", b""))
    print("wrote", OUT)


if __name__ == "__main__":
    main()
