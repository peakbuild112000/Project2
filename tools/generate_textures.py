#!/usr/bin/env python3
"""Generate the game's six tileable 256x256 RGB PNG textures.

The PNG encoder is written from scratch with zlib/struct (no Pillow, no
numpy). All patterns use periodic math or explicitly wrapped drawing so their
left/right and top/bottom edges match when repeated by Godot.
"""

import math
import os
import random
import struct
import zlib

SIZE = 256
TWO_PI = 2.0 * math.pi

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TEXTURE_DIR = os.path.join(ROOT, "assets", "textures")


# ---------------------------------------------------------------------------
# Minimal PNG encoder
# ---------------------------------------------------------------------------

def png_chunk(tag, data):
    """Length + type + payload + CRC32, exactly as specified by the PNG format."""
    return (struct.pack(">I", len(data)) + tag + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))


def write_png(path, pixels):
    """Encode a flat RGB bytearray as an 8-bit truecolor (type 2) PNG."""
    raw = bytearray()
    for y in range(SIZE):
        raw.append(0)  # filter type 0 (None) for every scanline
        start = y * SIZE * 3
        raw.extend(pixels[start:start + SIZE * 3])
    ihdr = struct.pack(">IIBBBBB", SIZE, SIZE, 8, 2, 0, 0, 0)
    png = bytearray(b"\x89PNG\r\n\x1a\n")
    png.extend(png_chunk(b"IHDR", ihdr))
    png.extend(png_chunk(b"IDAT", zlib.compress(bytes(raw), 9)))
    png.extend(png_chunk(b"IEND", b""))
    with open(path, "wb") as out:
        out.write(png)


# ---------------------------------------------------------------------------
# Pixel helpers (all drawing wraps around the texture edges)
# ---------------------------------------------------------------------------

def new_buffer():
    return bytearray(SIZE * SIZE * 3)


def clamp(v):
    return 0 if v < 0 else (255 if v > 255 else int(v))


def put(px, x, y, color, alpha=1.0):
    """Blend one pixel into the buffer; coordinates wrap in both directions."""
    idx = ((y % SIZE) * SIZE + (x % SIZE)) * 3
    for c in range(3):
        px[idx + c] = clamp(px[idx + c] * (1.0 - alpha) + color[c] * alpha)


def value_noise(cells, rng):
    """Smooth random field on a wrapping grid: fully periodic over 256 px."""
    grid = [[rng.random() for _ in range(cells)] for _ in range(cells)]
    out = [[0.0] * SIZE for _ in range(SIZE)]
    scale = cells / SIZE
    for y in range(SIZE):
        gy = y * scale
        y0 = int(gy) % cells
        y1 = (y0 + 1) % cells
        ty = gy - int(gy)
        sy = ty * ty * (3.0 - 2.0 * ty)
        for x in range(SIZE):
            gx = x * scale
            x0 = int(gx) % cells
            x1 = (x0 + 1) % cells
            tx = gx - int(gx)
            sx = tx * tx * (3.0 - 2.0 * tx)
            top = grid[y0][x0] * (1.0 - sx) + grid[y0][x1] * sx
            bottom = grid[y1][x0] * (1.0 - sx) + grid[y1][x1] * sx
            out[y][x] = top * (1.0 - sy) + bottom * sy
    return out


def brick_layout(x, y, brick_w=64, brick_h=32):
    """Return (local_x, local_y, column, row) for an offset brick pattern."""
    row = y // brick_h
    offset = (brick_w // 2) if row % 2 else 0
    shifted = x + offset
    return shifted % brick_w, y % brick_h, (shifted // brick_w) % (SIZE // brick_w), row


# ---------------------------------------------------------------------------
# Neon textures
# ---------------------------------------------------------------------------

def floor_neon(seed):
    rng = random.Random(seed)
    coarse = value_noise(8, rng)
    fine = value_noise(32, rng)
    px = new_buffer()
    for y in range(SIZE):
        for x in range(SIZE):
            v = 0.65 * coarse[y][x] + 0.35 * fine[y][x]
            base = (6 + int(8 * v), 12 + int(10 * v), 30 + int(22 * v))
            # Distance to the nearest grid line (period divides 256 exactly).
            dx = min(x % 32, 32 - (x % 32))
            dy = min(y % 32, 32 - (y % 32))
            glow = 0.55 * math.exp(-dx / 1.8) + 0.55 * math.exp(-dy / 1.8)
            core = (1 if dx == 0 else 0) + (1 if dy == 0 else 0)
            dot = math.exp(-(dx * dx + dy * dy) / 6.0)
            color = (base[0] + int(20 * glow + 35 * core + 60 * dot),
                     base[1] + int(150 * glow + 90 * core + 120 * dot),
                     base[2] + int(170 * glow + 110 * core + 130 * dot))
            put(px, x, y, color)
    return px


def wall_neon(seed):
    rng = random.Random(seed)
    grain = value_noise(16, rng)
    px = new_buffer()
    for y in range(SIZE):
        shade = 0.5 + 0.5 * math.cos(TWO_PI * (y % 128) / 128.0)
        hline = min(y % 128, 128 - (y % 128))
        h_glow = 0.45 * math.exp(-hline / 2.0)
        for x in range(SIZE):
            v = grain[y][x]
            base = (9 + int(7 * v + 4 * shade), 11 + int(7 * v),
                    28 + int(14 * v + 10 * shade))
            sx = x % 64
            seam = min(sx, 64 - sx)
            magenta = math.exp(-seam / 2.2)
            cyan = 0.8 * math.exp(-abs(sx - 3) / 1.6) + 0.8 * math.exp(-abs(sx - 61) / 1.6)
            color = (base[0] + int(190 * magenta + 18 * cyan + 55 * h_glow),
                     base[1] + int(45 * magenta + 120 * cyan + 90 * h_glow),
                     base[2] + int(165 * magenta + 140 * cyan + 110 * h_glow))
            if seam == 0:
                color = (235, 85, 215)
            put(px, x, y, color)
        # Small cyan rivets, repeated every 32 px vertically.
        for x in range(SIZE):
            if x % 64 == 32 and y % 32 == 16:
                put(px, x, y, (170, 245, 255), 0.9)
                put(px, x + 1, y, (80, 190, 220), 0.5)
                put(px, x - 1, y, (80, 190, 220), 0.5)
    return px


# ---------------------------------------------------------------------------
# Canyon textures
# ---------------------------------------------------------------------------

def floor_canyon(seed):
    rng = random.Random(seed)
    coarse = value_noise(8, rng)
    fine = value_noise(32, rng)
    px = new_buffer()
    for y in range(SIZE):
        for x in range(SIZE):
            # Integer wave counts plus a wrapping wobble keep strata tileable.
            strata = 0.5 + 0.5 * math.sin(TWO_PI * (5.0 * y / SIZE
                      + 0.12 * math.sin(TWO_PI * x / SIZE)))
            ribbons = 0.5 + 0.5 * math.sin(TWO_PI * (13.0 * y / SIZE
                      + 0.06 * math.sin(TWO_PI * 2.0 * x / SIZE)))
            v = 0.55 * coarse[y][x] + 0.45 * fine[y][x]
            color = (148 + int(34 * strata + 10 * ribbons + 26 * (v - 0.5)),
                     103 + int(28 * strata + 8 * ribbons + 22 * (v - 0.5)),
                     62 + int(20 * strata + 6 * ribbons + 16 * (v - 0.5)))
            put(px, x, y, color)
    # Wrapped sand speckles.
    for _ in range(1400):
        x, y = rng.randrange(SIZE), rng.randrange(SIZE)
        dark = rng.random() < 0.55
        color = (112, 78, 48) if dark else (212, 170, 118)
        put(px, x, y, color, 0.35 + 0.35 * rng.random())
    return px


def wall_canyon(seed):
    rng = random.Random(seed)
    grain = value_noise(16, rng)
    tints = [[rng.uniform(-14, 14) for _ in range(4)] for _ in range(8)]
    px = new_buffer()
    for y in range(SIZE):
        for x in range(SIZE):
            lx, ly, col, row = brick_layout(x, y)
            v = grain[y][x]
            if lx < 3 or ly < 3:
                color = (104 + int(14 * v), 72 + int(12 * v), 44 + int(10 * v))
            else:
                tint = tints[row % 8][col % 4]
                band = 0.5 + 0.5 * math.sin(TWO_PI * ly / 8.0)
                edge = 12 if (lx == 3 or ly == 3) else 0
                color = (152 + int(tint + 18 * band + 20 * (v - 0.5)) + edge,
                         107 + int(tint + 14 * band + 16 * (v - 0.5)) + edge,
                         66 + int(0.7 * tint + 10 * band + 12 * (v - 0.5)) + edge)
            put(px, x, y, color)
    for _ in range(1100):
        x, y = rng.randrange(SIZE), rng.randrange(SIZE)
        color = (92, 62, 38) if rng.random() < 0.6 else (206, 164, 112)
        put(px, x, y, color, 0.30 + 0.30 * rng.random())
    return px


# ---------------------------------------------------------------------------
# Frost textures
# ---------------------------------------------------------------------------

def draw_crack(px, rng):
    """Random walk drawn with wrapped coordinates, so it survives tiling."""
    x, y = rng.randrange(SIZE), rng.randrange(SIZE)
    angle = rng.uniform(0.0, TWO_PI)
    steps = rng.randrange(28, 80)
    for _ in range(steps):
        angle += rng.uniform(-0.32, 0.32)
        step = rng.uniform(2.5, 5.5)
        x += math.cos(angle) * step
        y += math.sin(angle) * step
        ix, iy = int(x) % SIZE, int(y) % SIZE
        put(px, ix, iy, (236, 248, 255), 0.35)   # frosty halo
        put(px, ix, iy, (110, 150, 182), 0.55)   # crack core
        if rng.random() < 0.12:
            put(px, ix + 1, iy, (120, 160, 195), 0.35)


def floor_frost(seed):
    rng = random.Random(seed)
    coarse = value_noise(8, rng)
    fine = value_noise(32, rng)
    px = new_buffer()
    for y in range(SIZE):
        for x in range(SIZE):
            v = 0.6 * coarse[y][x] + 0.4 * fine[y][x]
            put(px, x, y, (192 + int(28 * v), 214 + int(22 * v), 228 + int(26 * v)))
    for _ in range(16):
        draw_crack(px, rng)
    for _ in range(500):
        x, y = rng.randrange(SIZE), rng.randrange(SIZE)
        put(px, x, y, (250, 253, 255), 0.35 + 0.35 * rng.random())
    return px


def wall_frost(seed):
    rng = random.Random(seed)
    coarse = value_noise(16, rng)
    fine = value_noise(64, rng)
    tints = [[rng.uniform(-12, 12) for _ in range(4)] for _ in range(8)]
    px = new_buffer()
    for y in range(SIZE):
        for x in range(SIZE):
            lx, ly, col, row = brick_layout(x, y)
            v = 0.6 * coarse[y][x] + 0.4 * fine[y][x]
            if lx < 3 or ly < 3:
                color = (168 + int(20 * v), 198 + int(18 * v), 218 + int(20 * v))
            else:
                tint = tints[row % 8][col % 4]
                band = 0.5 + 0.5 * math.sin(TWO_PI * ly / 8.0)
                color = (198 + int(tint + 10 * band + 26 * (v - 0.5)),
                         222 + int(tint + 8 * band + 22 * (v - 0.5)),
                         236 + int(tint + 6 * band + 20 * (v - 0.5)))
            put(px, x, y, color)
    # Fine frost crystals and a few hairline cracks.
    for _ in range(900):
        x, y = rng.randrange(SIZE), rng.randrange(SIZE)
        put(px, x, y, (250, 254, 255), 0.20 + 0.35 * rng.random())
    for _ in range(6):
        draw_crack(px, rng)
    return px


def main():
    os.makedirs(TEXTURE_DIR, exist_ok=True)
    textures = (
        ("floor_neon.png", floor_neon, 101),
        ("wall_neon.png", wall_neon, 202),
        ("floor_canyon.png", floor_canyon, 303),
        ("wall_canyon.png", wall_canyon, 404),
        ("floor_frost.png", floor_frost, 505),
        ("wall_frost.png", wall_frost, 606),
    )
    for name, factory, seed in textures:
        path = os.path.join(TEXTURE_DIR, name)
        write_png(path, factory(seed))
        print("wrote", os.path.relpath(path, ROOT))


if __name__ == "__main__":
    main()
