#!/usr/bin/env python3
"""Generate Packaging/AppIcon.png (1024x1024) — pure stdlib, no deps.

Branded scenery motif (teal→deep-blue gradient + warm sun + dark hill) that
reads as a "desktop wallpaper" and matches the IHaven teal/blue business theme.
Output is a square PNG; macOS applies the app-icon rounded mask at render time.
"""
import struct
import zlib
import math
import os

S = 1024
top = (31, 182, 166)    # teal
bot = (30, 58, 138)     # deep blue
sun = (255, 245, 220)   # warm light
hill = (15, 32, 72)     # dark base


def lerp(a, b, t):
    return a + (b - a) * t


def px(x, y):
    ny = y / S
    r = lerp(top[0], bot[0], ny)
    g = lerp(top[1], bot[1], ny)
    b = lerp(top[2], bot[2], ny)

    # Sun: soft circle, upper-right
    sx, sy, sr = 0.70 * S, 0.34 * S, 0.17 * S
    d = math.hypot(x - sx, y - sy)
    if d < sr:
        t = 1 - d / sr
        a = (t ** 0.6) * 0.95
        r = lerp(r, sun[0], a); g = lerp(g, sun[1], a); b = lerp(b, sun[2], a)

    # Hill: gentle curved baseline near bottom
    hill_top = S * 0.74 - 0.10 * S * math.sin((x / S) * math.pi)
    if y > hill_top:
        ht = (y - hill_top) / (S - hill_top)
        a = 0.55 + 0.45 * ht
        r = lerp(r, hill[0], a); g = lerp(g, hill[1], a); b = lerp(b, hill[2], a)

    return int(max(0, min(255, r))), int(max(0, min(255, g))), int(max(0, min(255, b)))


def chunk(typ, data):
    c = struct.pack(">I", len(data)) + typ + data
    c += struct.pack(">I", zlib.crc32(typ + data) & 0xffffffff)
    return c


def main():
    raw = bytearray()
    for y in range(S):
        raw.append(0)  # filter: none
        for x in range(S):
            r, g, b = px(x, y)
            raw += bytes((r, g, b))

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", S, S, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    png += chunk(b"IEND", b"")

    out_dir = os.path.join(os.path.dirname(__file__), "..", "Packaging")
    os.makedirs(out_dir, exist_ok=True)
    out_path = os.path.join(out_dir, "AppIcon.png")
    with open(out_path, "wb") as f:
        f.write(png)
    print(f"wrote {out_path} ({len(png)} bytes)")


if __name__ == "__main__":
    main()
