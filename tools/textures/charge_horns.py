"""The Minotaur's head seen from above, as a smooth white silhouette on transparency: the mark repeated
along his Devastating Charge lane (HeroVisuals.Minotaur tints it red). Plain Python, no libraries.

The picture's top is the way he charges. Its 2:1 shape covers 13.2 x 6.6 studs on the lane (the lane
is 14 wide), so the shapes below are in studs: x across, z ahead.
  - the skull: a broad rounded shield, narrowing behind into the muzzle
  - two stout horns: thick at the skull, going almost straight out, then hooking forward and
    tapering to blunt tips at the front corners
Edges are anti-aliased from each shape's distance to the pixel.

usage: python3 charge_horns.py <out.png> [width]      (default width 1024)
"""
import math, struct, sys, zlib

OUT = sys.argv[1]
W = int(sys.argv[2]) if len(sys.argv) > 2 else 1024
H = W // 2
HALF_X, HALF_Z = 6.6, 3.3                 # studs from the middle to the edges
PX = W / (2 * HALF_X)                     # pixels per stud

alpha = [0.0] * (W * H)


def to_px(x, z):
    return (x + HALF_X) * PX, (HALF_Z - z) * PX      # (image y runs down; z ahead is up)


def disc(cx, cz, r):
    """An anti-aliased filled circle (studs), merged in (the brighter wins)."""
    px, py = to_px(cx, cz)
    rp = r * PX
    x0, x1 = max(0, int(px - rp - 2)), min(W - 1, int(px + rp + 2))
    y0, y1 = max(0, int(py - rp - 2)), min(H - 1, int(py + rp + 2))
    for y in range(y0, y1 + 1):
        dy = y + 0.5 - py
        row = y * W
        for x in range(x0, x1 + 1):
            dx = x + 0.5 - px
            c = rp - math.sqrt(dx * dx + dy * dy) + 0.5
            if c > 0:
                c = 1.0 if c > 1 else c
                if c > alpha[row + x]:
                    alpha[row + x] = c


def ellipse(cx, cz, rx, rz):
    """An anti-aliased filled ellipse (studs)."""
    px, py = to_px(cx, cz)
    rxp, ryp = rx * PX, rz * PX
    x0, x1 = max(0, int(px - rxp - 2)), min(W - 1, int(px + rxp + 2))
    y0, y1 = max(0, int(py - ryp - 2)), min(H - 1, int(py + ryp + 2))
    m = min(rxp, ryp)
    for y in range(y0, y1 + 1):
        dy = (y + 0.5 - py) / ryp
        row = y * W
        for x in range(x0, x1 + 1):
            dx = (x + 0.5 - px) / rxp
            c = (1 - math.sqrt(dx * dx + dy * dy)) * m + 0.5     # (roughly the distance in pixels)
            if c > 0:
                c = 1.0 if c > 1 else c
                if c > alpha[row + x]:
                    alpha[row + x] = c


def bezier(p0, p1, p2, p3, t):
    u = 1 - t
    return tuple(u ** 3 * a + 3 * u * u * t * b + 3 * u * t * t * c + t ** 3 * d
                 for a, b, c, d in zip(p0, p1, p2, p3))


def horn(side):
    """A horn: circles packed along a curve, shrinking toward the tip (a smooth tapering tube)."""
    s = side
    p0, p1, p2, p3 = (1.5 * s, 0.55), (4.1 * s, 0.25), (6.05 * s, 0.85), (5.95 * s, 2.95)
    steps = 160
    for i in range(steps + 1):
        t = i / steps
        x, z = bezier(p0, p1, p2, p3, t)
        r = 1.2 * (1 - t) ** 0.85 + 0.2 * t            # thick at the skull, blunt at the tip
        disc(x, z, r)


# the skull: a broad shield (brow forward), and the muzzle behind it
ellipse(0, -0.45, 2.3, 2.15)
ellipse(0, -1.85, 1.7, 1.4)
horn(-1)
horn(1)

# PNG: white, alpha = coverage
raw = bytearray()
for y in range(H):
    raw.append(0)                                  # (no filter)
    row = y * W
    for x in range(W):
        raw += bytes((255, 255, 255, int(alpha[row + x] * 255 + 0.5)))


def chunk(kind, data):
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xffffffff)


png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", W, H, 8, 6, 0, 0, 0)) \
    + chunk(b"IDAT", zlib.compress(bytes(raw), 9)) + chunk(b"IEND", b"")
with open(OUT, "wb") as f:
    f.write(png)
print(f"wrote {OUT} ({W}x{H})")
