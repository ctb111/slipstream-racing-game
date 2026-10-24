#!/usr/bin/env python3
"""Bakes the graffiti atlases for scripts/track/gimmicks/gx_graffiti.gd.

  assets/gimmicks/gx_graffiti_walls.png  RGBA 2048x4096, 16 cells of 1024x512 (2 cols x 8 rows):
        real photographed graffiti walls (Wikimedia Commons, CC BY-SA / CC0; see CREDITS.txt),
        cropped to the painted wall, levelled; alpha = ragged spray-edge mask (decal use).
        Cell 15 = plain weathered concrete (Poly Haven concrete_wall_008, CC0).
  assets/gimmicks/gx_graffiti_tags.png   RGBA 2048x2048, 16 cells of 512x512 (4x4):
        hand-drawn tags from ambientCG GraffitiSet001 (CC0), white (tinted at runtime),
        with overspray haze and drips.
Source photos live in assets/gimmicks/src (git-ignored by Godot via .gdignore).
Run:  /path/to/python-with-pillow-numpy tools/make_gx_graffiti.py
"""
import os, random
import numpy as np
from PIL import Image, ImageFilter, ImageOps, ImageChops

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
SRC = os.path.join(ROOT, "assets/gimmicks/src")
OUT = os.path.join(ROOT, "assets/gimmicks")
rnd = random.Random(3)
CW, CH = 1024, 512

# file, crop box (fractions x0, y0, x1, y1)
WALLS = [
    ("g142.jpg", (0.06, 0.37, 0.97, 0.89)),
    ("g143.jpg", (0.05, 0.40, 0.95, 0.86)),
    ("g144.jpg", (0.05, 0.44, 0.94, 0.88)),
    ("g145.jpg", (0.03, 0.30, 0.97, 0.89)),
    ("g146.jpg", (0.05, 0.30, 0.93, 0.93)),
    ("g149.jpg", (0.03, 0.17, 0.97, 0.90)),
    ("g150.jpg", (0.03, 0.30, 0.97, 0.90)),
    ("g151.jpg", (0.03, 0.30, 0.97, 0.90)),
    ("g152.jpg", (0.11, 0.33, 0.95, 0.88)),
    ("g156.jpg", (0.25, 0.05, 0.85, 0.95)),
    ("g138.jpg", (0.07, 0.38, 0.93, 0.95)),
    ("g141.jpg", (0.07, 0.32, 0.93, 0.98)),
    ("g162.jpg", (0.00, 0.05, 1.00, 0.70)),
    ("g003.jpg", (0.05, 0.20, 0.95, 0.80)),
    ("g008.jpg", (0.00, 0.15, 0.50, 0.42)),
]


def level(im):
    """Even out the baked lighting: remove the large-scale brightness gradient
    (shade under the bridge deck) and stretch levels a little."""
    a = np.asarray(im).astype(np.float32) / 255.0
    lum = a.mean(axis=2)
    big = np.asarray(Image.fromarray((lum * 255).astype(np.uint8)).resize((8, 4), Image.BILINEAR)
                     .resize(im.size, Image.BILINEAR)).astype(np.float32) / 255.0
    target = lum.mean()
    gain = np.clip(target / np.maximum(big, 0.05), 0.75, 1.35) ** 0.6
    a = a * gain[..., None]
    lo, hi = np.percentile(a, 0.5), np.percentile(a, 99.6)
    a = np.clip((a - lo) / max(hi - lo, 0.1), 0, 1)
    a = a ** 0.95
    # punchier colour so the pieces read from 50 m: +20% saturation, slight S-curve
    l = a.mean(axis=2, keepdims=True)
    a = np.clip(l + (a - l) * 1.2, 0, 1)
    a = np.clip(0.5 + (a - 0.5) * 1.08, 0, 1)
    return Image.fromarray((a * 255).astype(np.uint8))


def ragged_mask(w, h, edge=0.05, seed=0):
    r = np.random.RandomState(seed)
    y, x = np.mgrid[0:h, 0:w].astype(np.float32)
    d = np.minimum.reduce([x / w, (w - 1 - x) / w, y / h * (h / w), (h - 1 - y) / h * (h / w)])
    nz = r.rand(h // 16 + 1, w // 16 + 1).astype(np.float32)
    nz = np.asarray(Image.fromarray((nz * 255).astype(np.uint8)).resize((w, h), Image.BICUBIC)).astype(np.float32) / 255.0
    fine = r.rand(h, w).astype(np.float32)
    m = np.clip((d - edge * 0.25 - nz * edge * 0.6) / (edge * 0.5), 0, 1)
    m = m * (0.85 + 0.15 * fine) if True else m
    m = np.where(m > 0.98, 1.0, m)
    return Image.fromarray((m * 255).astype(np.uint8))


def walls():
    atlas = Image.new("RGBA", (CW * 2, CH * 8), (0, 0, 0, 0))
    for i, (fn, (x0, y0, x1, y1)) in enumerate(WALLS):
        im = Image.open(os.path.join(SRC, fn)).convert("RGB")
        w, h = im.size
        im = im.crop((int(x0 * w), int(y0 * h), int(x1 * w), int(y1 * h))).resize((CW, CH), Image.LANCZOS)
        im = level(im)
        im.putalpha(ragged_mask(CW, CH, seed=i))
        atlas.paste(im, ((i % 2) * CW, (i // 2) * CH))
    # cell 15: plain weathered concrete from the stencil-wall photo
    con = Image.open(os.path.join(SRC, "g003.jpg")).convert("RGB")
    w, h = con.size
    cell = level(con.crop((0, 0, int(w * 0.4), int(h * 0.25))).resize((CW, CH), Image.LANCZOS))  # bare band above the stencil
    a = np.asarray(cell).astype(np.float32)
    g = np.linspace(1.0, 0.82, CH)[:, None, None]
    cell = Image.fromarray(np.clip(a * g, 0, 255).astype(np.uint8)).convert("RGBA")
    atlas.paste(cell, (CW, 7 * CH))
    atlas.save(os.path.join(OUT, "gx_graffiti_walls.png"), optimize=True)


def tags():
    col = Image.open(os.path.join(SRC, "GraffitiSet001_Opacity.png")).convert("L")
    S = col.size[0] // 4
    atlas = Image.new("RGBA", (2048, 2048), (0, 0, 0, 0))
    for i in range(16):
        cx, cy = (i % 4) * S, (i // 4) * S
        a = col.crop((cx, cy, cx + S, cy + S)).resize((512, 512), Image.LANCZOS)
        an = np.asarray(a).astype(np.float32) / 255.0
        # overspray: soft haze around strokes + fine speckle
        haze = np.asarray(a.filter(ImageFilter.GaussianBlur(9))).astype(np.float32) / 255.0
        r = np.random.RandomState(i)
        speck = (r.rand(512, 512) < haze * 0.25).astype(np.float32) * 0.5
        # drips: short vertical runs under heavy strokes
        drip = np.zeros_like(an)
        cols = r.choice(512, 6, replace=False)
        for c in cols:
            ys = np.nonzero(an[:, c] > 0.8)[0]
            if len(ys):
                y0 = ys.max(); L = r.randint(10, 45)
                drip[y0:min(512, y0 + L), max(0, c - 1):c + 2] = np.linspace(0.9, 0.0, min(512, y0 + L) - y0)[:, None]
        # uneven coverage inside the strokes
        cover = 0.82 + 0.18 * np.asarray(Image.fromarray((r.rand(32, 32) * 255).astype(np.uint8)).resize((512, 512), Image.BICUBIC)).astype(np.float32) / 255.0
        alpha = np.clip(np.maximum.reduce([an * cover, haze * 0.18, speck, drip]), 0, 1)
        rgb = np.full((512, 512, 3), 255, np.uint8)
        cell = np.dstack([rgb, (alpha * 255).astype(np.uint8)])
        atlas.paste(Image.fromarray(cell, "RGBA"), ((i % 4) * 512, (i // 4) * 512))
    atlas.save(os.path.join(OUT, "gx_graffiti_tags.png"), optimize=True)


if __name__ == "__main__":
    walls()
    tags()
    print("ok")
