#!/usr/bin/env python3
"""Bakes the fan road-paint atlas for scripts/track/gimmicks/gx_road_text.gd.

  assets/gimmicks/gx_road_text.png  RGBA 2048x2048, white paint (tinted white / yellow at runtime):
     y 0..1023    glyphs, 128x128 cells, 16 per row: variant 0 rows 0-3, variant 1 rows 4-7
     y 1024..2047 symbols, 256x256 cells, 8 per row (SYMBOLS order)
  scripts/track/gimmicks/gx_road_glyphs.gd  (generated) glyph order + advance widths

Letters: Permanent Marker (Apache 2.0, assets/trackside/src/fonts), then roughened like
roller / brush paint on tarmac: ragged edges, streaky coverage, aggregate showing through.
"""
import os, math
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
FONT = os.path.join(ROOT, "assets/trackside/src/fonts/PermanentMarker-Regular.ttf")
CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!?.-'&+#ÄÖÜØÅÉÈÀÑÇÆŁŠČŽß♥"
SYMBOLS = ["heart", "heart2", "arrow", "arrow2", "flag", "chevrons", "star", "tricolor"]
SS = 2
G = 128


def paintify(mask, seed, streak_dir=0):
    """mask: L image (supersampled). Returns float alpha 0..1 at the same size."""
    r = np.random.RandomState(seed)
    h, w = mask.size[1], mask.size[0]
    a = np.asarray(mask.filter(ImageFilter.GaussianBlur(2.5 * SS))).astype(np.float32) / 255.0
    edge_nz = r.rand(h // 6 + 1, w // 6 + 1).astype(np.float32)
    edge_nz = np.asarray(Image.fromarray((edge_nz * 255).astype(np.uint8)).resize((w, h), Image.BICUBIC)).astype(np.float32) / 255.0
    a = np.clip((a - 0.5 + (edge_nz - 0.5) * 0.35) * 6.0 + 0.5, 0, 1)
    # streaks along the brush direction (vertical in the cell = along the road)
    st = r.rand(h // 40 + 1, w // 3 + 1).astype(np.float32) if streak_dir == 0 else r.rand(h // 3 + 1, w // 40 + 1).astype(np.float32)
    st = np.asarray(Image.fromarray((st * 255).astype(np.uint8)).resize((w, h), Image.BICUBIC)).astype(np.float32) / 255.0
    a *= 0.72 + 0.28 * st
    # aggregate showing through: small holes, more at the edges
    holes = r.rand(h, w).astype(np.float32)
    holes = np.asarray(Image.fromarray((holes * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.0))).astype(np.float32) / 255.0
    a *= np.clip((holes - 0.33) * 9.0, 0.35, 1.0)
    # worn patches (tyres)
    wear = r.rand(h // 30 + 1, w // 30 + 1).astype(np.float32)
    wear = np.asarray(Image.fromarray((wear * 255).astype(np.uint8)).resize((w, h), Image.BICUBIC)).astype(np.float32) / 255.0
    a *= np.clip(0.55 + wear * 0.8, 0, 1)
    # a few spatters around
    for _ in range(r.randint(0, 3)):
        x, y = r.randint(0, w), r.randint(0, h)
        rr = r.uniform(1.0, 3.5) * SS
        yy, xx = np.ogrid[:h, :w]
        a = np.maximum(a, ((xx - x) ** 2 + (yy - y) ** 2 < rr * rr).astype(np.float32) * 0.7)
    return np.clip(a, 0, 1)


def glyph(ch, variant):
    S = G * SS
    im = Image.new("L", (S, S), 0)
    d = ImageDraw.Draw(im)
    if ch == "♥":
        heart(d, S, 0.12)
        adv = 0.95
    else:
        f = ImageFont.truetype(FONT, int(S * 0.78))
        bb = d.textbbox((0, 0), ch, font=f)
        tw = bb[2] - bb[0]
        x = (S - tw) / 2 - bb[0]
        y = S * 0.88 - bb[3]
        d.text((x, y), ch, font=f, fill=255)
        adv = min(1.0, max(0.35, (tw / S) + 0.12))
    im = im.filter(ImageFilter.MaxFilter(9))  # fat roller strokes, readable at speed
    im = im.rotate((variant * 2 - 1) * 2.5, resample=Image.BICUBIC)
    a = paintify(im, hash((ch, variant)) % 100000)
    return Image.fromarray((a * 255).astype(np.uint8)).resize((G, G), Image.LANCZOS), adv


def heart(d, S, m):
    pts = []
    for i in range(80):
        t = i / 80 * 2 * math.pi
        x = 16 * math.sin(t) ** 3
        y = 13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)
        pts.append((S / 2 + x / 34 * S * (1 - m), S * 0.47 - y / 34 * S * (1 - m)))
    d.polygon(pts, fill=255)


def symbol(name, seed):
    S = 256 * SS
    im = Image.new("L", (S, S), 0)
    d = ImageDraw.Draw(im)
    if name.startswith("heart"):
        heart(d, S, 0.08 if name == "heart" else 0.1)
        if name == "heart2":  # outline heart (painted ring)
            inner = Image.new("L", (S, S), 0)
            heart(ImageDraw.Draw(inner), S, 0.32)
            im = Image.fromarray(np.clip(np.asarray(im).astype(int) - np.asarray(inner).astype(int), 0, 255).astype(np.uint8))
            d = ImageDraw.Draw(im)
    elif name.startswith("arrow"):  # pointing up = along the road
        w = 0.16 if name == "arrow" else 0.11
        d.rectangle([S * (0.5 - w / 2), S * 0.38, S * (0.5 + w / 2), S * 0.95], fill=255)
        d.polygon([(S * 0.5, S * 0.04), (S * 0.86, S * 0.44), (S * 0.14, S * 0.44)], fill=255)
    elif name == "flag":  # checkered panel, 4x6 squares
        n, m = 4, 6
        for i in range(n):
            for j in range(m):
                if (i + j) % 2 == 0:
                    d.rectangle([S * (0.12 + i * 0.76 / n), S * (0.04 + j * 0.92 / m), S * (0.12 + (i + 1) * 0.76 / n), S * (0.04 + (j + 1) * 0.92 / m)], fill=255)
        d.rectangle([S * 0.1, S * 0.03, S * 0.9, S * 0.97], outline=255, width=int(S * 0.02))
    elif name == "chevrons":
        for k in range(3):
            y = S * (0.1 + k * 0.28)
            d.line([(S * 0.15, y + S * 0.22), (S * 0.5, y), (S * 0.85, y + S * 0.22)], fill=255, width=int(S * 0.08), joint="curve")
    elif name == "star":
        pts = []
        for i in range(10):
            rr = S * (0.46 if i % 2 == 0 else 0.19)
            a = -math.pi / 2 + i * math.pi / 5
            pts.append((S / 2 + math.cos(a) * rr, S / 2 + math.sin(a) * rr))
        d.polygon(pts, fill=255)
    elif name == "tricolor":  # three painted stripes (any national colours via 3 quads tint)
        for k in range(3):
            d.rectangle([S * (0.08 + k * 0.29), S * 0.05, S * (0.33 + k * 0.29), S * 0.95], fill=255 if k != 1 else 170)
    a = paintify(im, seed, 0)
    return Image.fromarray((a * 255).astype(np.uint8)).resize((256, 256), Image.LANCZOS)


def main():
    atlas = np.zeros((2048, 2048), np.uint8)
    advs = []
    for v in range(2):
        for i, ch in enumerate(CHARS):
            g, adv = glyph(ch, v)
            x, y = (i % 16) * G, (v * 4 + i // 16) * G
            atlas[y:y + G, x:x + G] = np.asarray(g)
            if v == 0:
                advs.append(adv)
    for i, s in enumerate(SYMBOLS):
        x, y = (i % 8) * 256, 1024 + (i // 8) * 256
        atlas[y:y + 256, x:x + 256] = np.asarray(symbol(s, 500 + i))
    rgba = np.dstack([np.full((2048, 2048, 3), 255, np.uint8), atlas])
    Image.fromarray(rgba, "RGBA").save(os.path.join(ROOT, "assets/gimmicks/gx_road_text.png"), optimize=True)
    with open(os.path.join(ROOT, "scripts/track/gimmicks/gx_road_glyphs.gd"), "w") as f:
        f.write("class_name GxRoadGlyphs\nextends RefCounted\n## GENERATED by tools/make_gx_road_text.py: glyph order and advance widths (x cell).\n\n")
        f.write("const CHARS := \"%s\"\n" % CHARS)
        f.write("const ADV := [%s]\n" % ", ".join("%.3f" % a for a in advs))
        f.write("const SYMBOLS := [%s]\n" % ", ".join('"%s"' % s for s in SYMBOLS))
    print("ok", len(CHARS))


if __name__ == "__main__":
    main()
