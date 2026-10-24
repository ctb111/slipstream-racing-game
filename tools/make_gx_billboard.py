#!/usr/bin/env python3
"""Bakes assets/gimmicks/gx_billboard.png (RGB 2048x4096) for scripts/track/gimmicks/gx_billboard.gd.

Top: 8 weathered paper billboard posters (1024x724 each, 2 cols x 4 rows) for the game's invented
brands, built on real photographs (Wikimedia Commons, CC0 / CC BY / CC BY-SA, see assets/CREDITS.txt)
with the bundled Barlow Semi Condensed fonts (OFL). Bottom (y >= 2944): road signs, cell layout in
SIGNS below (pixel rects, mirrored in gx_billboard.gd).
Run: python-with-pillow-numpy tools/make_gx_billboard.py
"""
import os, random
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageEnhance, ImageOps

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
SRC = os.path.join(ROOT, "assets/gimmicks/src")
FONT = os.path.join(ROOT, "assets/fonts/BarlowSemiCondensed-%s.ttf")
PW, PH = 1024, 724
SS = 2  # supersampling for type and vector shapes
rnd = random.Random(11)


def F(w, size):
    return ImageFont.truetype(FONT % w, size)


def cover(path, w, h, focus=(0.5, 0.5)):
    im = Image.open(os.path.join(SRC, path)).convert("RGB")
    s = max(w / im.width, h / im.height)
    im = im.resize((int(im.width * s + 1), int(im.height * s + 1)), Image.LANCZOS)
    x = int((im.width - w) * focus[0]); y = int((im.height - h) * focus[1])
    return im.crop((x, y, x + w, y + h))


def tracked(d, xy, text, font, fill, track=0.0, anchor="l"):
    """Text with letter spacing (track in em). anchor l / m / r on x, top on y."""
    widths = [font.getlength(ch) for ch in text]
    total = sum(widths) + track * font.size * (len(text) - 1)
    x, y = xy
    if anchor == "m":
        x -= total / 2
    elif anchor == "r":
        x -= total
    for ch, wd in zip(text, widths):
        d.text((x, y), ch, font=font, fill=fill)
        x += wd + track * font.size
    return total


def grad(w, h, c0, c1, a0, a1, vertical=True):
    """RGBA gradient overlay from (c0, a0) to (c1, a1)."""
    t = np.linspace(0, 1, h if vertical else w)
    t = t[:, None] if vertical else t[None, :]
    t = np.broadcast_to(t, (h, w))
    c0 = np.array(c0, np.float32); c1 = np.array(c1, np.float32)
    rgb = c0[None, None, :] * (1 - t[..., None]) + c1[None, None, :] * t[..., None]
    a = a0 * (1 - t) + a1 * t
    return Image.fromarray(np.dstack([rgb, a * 255]).astype(np.uint8), "RGBA")


def poster(brand):
    W, H = PW * SS, PH * SS
    img = cover(brand["photo"], W, H, brand.get("focus", (0.5, 0.5)))
    img = ImageEnhance.Contrast(img).enhance(brand.get("contrast", 1.05))
    img = img.convert("RGBA")
    for g in brand.get("grads", []):
        img = Image.alpha_composite(img, grad(W, H, *g))
    d = ImageDraw.Draw(img)
    brand["draw"](img, d, W, H)
    return img.convert("RGB").resize((PW, PH), Image.LANCZOS)


def weather(img, seed):
    """Paper billboard wear: pasted sheet seams, sun fade, dirt runs, a torn strip."""
    r = np.random.RandomState(seed)
    a = np.asarray(img).astype(np.float32) / 255.0
    h, w, _ = a.shape
    # sun fade: lift blacks, slight desaturation and warm shift
    lum = a.mean(axis=2, keepdims=True)
    a = a * 0.9 + lum * 0.1
    a = a * 0.93 + 0.05
    a[..., 2] *= 0.97
    # sheet seams (18/1 poster: 4 x 3 sheets) with tiny misregistration
    for k in range(1, 4):
        x = int(w * k / 4 + r.randint(-3, 4))
        a[:, x:x + 2] = a[:, x:x + 2] * 0.7 + 0.25
        sh = r.randint(-2, 3)
        a[:, x + 2:] = np.roll(a[:, x + 2:], sh, axis=0) if k == 2 else a[:, x + 2:]
    for k in range(1, 3):
        y = int(h * k / 3 + r.randint(-3, 4))
        a[y:y + 2, :] = a[y:y + 2, :] * 0.72 + 0.22
    # paper wrinkle / blotch noise
    nz = r.rand(h // 24 + 1, w // 24 + 1).astype(np.float32)
    nz = np.asarray(Image.fromarray((nz * 255).astype(np.uint8)).resize((w, h), Image.BICUBIC)).astype(np.float32) / 255.0
    a *= (0.95 + 0.07 * nz)[..., None]
    # dirt runs from the top frame
    for _ in range(r.randint(8, 16)):
        x = r.randint(0, w - 6); L = r.randint(h // 8, h // 2); wd = r.randint(2, 7)
        fade = np.linspace(0.16, 0.0, L)[:, None, None] * r.uniform(0.4, 1.0)
        a[:L, x:x + wd] *= (1 - fade)
    top = np.linspace(0.82, 1.0, 60)[:, None, None]
    a[:60] *= top
    # one torn / peeling strip on some posters: old white paper underneath
    if r.rand() < 0.45:  # a small peeled corner: old paper underneath
        tw = r.randint(30, 70); th = r.randint(14, 40)
        x0 = r.choice([0, w - tw]); y0 = r.choice([0, h - th])
        mask = Image.new("L", (w, h), 0)
        md = ImageDraw.Draw(mask)
        pts = [(x0 + r.randint(-4, 4) + tw * i / 6, y0 + (th if y0 == 0 else 0) * (1 - abs(i - 3) / 4) + r.randint(-5, 5)) for i in range(7)]
        if y0 == 0:
            md.polygon([(x0, 0), *pts, (x0 + tw, 0)], fill=255)
        else:
            md.polygon([(x0, h), *pts, (x0 + tw, h)], fill=255)
        m = np.asarray(mask.filter(ImageFilter.GaussianBlur(1.2))).astype(np.float32)[..., None] / 255.0
        paper = np.array([0.86, 0.85, 0.8])
        a = a * (1 - m) + paper * m * (0.9 + 0.1 * nz[..., None])
    return Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8))


# ---- brand layouts -------------------------------------------------------------------------

def sun(d, cx, cy, r, col, rays=12):
    import math
    for i in range(rays):
        a = i / rays * 2 * math.pi
        a2 = a + math.pi / rays * 0.55
        a3 = a - math.pi / rays * 0.55
        d.polygon([(cx + math.cos(a) * r * 1.75, cy + math.sin(a) * r * 1.75),
                   (cx + math.cos(a2) * r * 1.15, cy + math.sin(a2) * r * 1.15),
                   (cx + math.cos(a3) * r * 1.15, cy + math.sin(a3) * r * 1.15)], fill=col)
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=col)


def d_marzelli(img, d, W, H):
    wine = (92, 16, 20); cream = (238, 226, 200)
    d.rectangle([0, H * 0.70, W, H], fill=wine)
    d.rectangle([0, H * 0.70, W, H * 0.70 + 6], fill=(196, 160, 90))
    tracked(d, (W * 0.06, H * 0.735), "MARZELLI", F("Bold", 210), cream, 0.06)
    tracked(d, (W * 0.065, H * 0.905), "ESPRESSO ITALIANO  ·  DAL 1921", F("Medium", 54), (214, 186, 130), 0.18)
    tracked(d, (W * 0.94, H * 0.08), "Il gusto della velocità.", F("SemiBold", 70), cream, 0.01, "r")


def d_nordlicht(img, d, W, H):
    green = (14, 52, 34); gold = (205, 168, 76)
    d.rectangle([W * 0.58, 0, W, H], fill=green + (235,))
    d.rectangle([W * 0.58, 0, W * 0.58 + 8, H], fill=gold)
    tracked(d, (W * 0.79, H * 0.20), "NORDLICHT", F("Bold", 150), (240, 238, 228), 0.04, "m")
    tracked(d, (W * 0.79, H * 0.37), "PREMIUM PILS", F("SemiBold", 70), gold, 0.3, "m")
    d.line([W * 0.66, H * 0.50, W * 0.92, H * 0.50], fill=gold, width=4)
    tracked(d, (W * 0.79, H * 0.56), "Klar wie", F("Medium", 84), (232, 230, 220), 0.0, "m")
    tracked(d, (W * 0.79, H * 0.66), "der Norden.", F("Medium", 84), (232, 230, 220), 0.0, "m")
    tracked(d, (W * 0.79, H * 0.88), "GEBRAUT SEIT 1874", F("Medium", 40), gold, 0.25, "m")


def d_helios(img, d, W, H):
    orange = (226, 104, 22); ink = (20, 18, 16)
    d.rectangle([0, 0, W, H * 0.22], fill=(242, 236, 222))
    sun(d, W * 0.09, H * 0.11, H * 0.055, orange)
    tracked(d, (W * 0.16, H * 0.025), "HELIOS", F("Bold", 200), ink, 0.04)
    tracked(d, (W * 0.16 + F("Bold", 200).getlength("HELIOS") * 1.0 + 160, H * 0.06), "BENZIN", F("SemiBold", 130), orange, 0.12)
    d.rectangle([0, H * 0.22, W, H * 0.22 + 10], fill=orange)
    tracked(d, (W * 0.06, H * 0.76), "Volle Kraft.", F("Bold", 118), (255, 255, 255), 0.0)
    tracked(d, (W * 0.06, H * 0.86), "Jede Kurve.", F("Bold", 118), (255, 196, 120), 0.0)
    tracked(d, (W * 0.95, H * 0.92), "SUPER  98", F("SemiBold", 56), (255, 255, 255), 0.2, "r")


def d_valter(img, d, W, H):
    navy = (16, 26, 58); red = (170, 26, 22); cream = (236, 228, 206)
    d.polygon([(0, H * 0.62), (W, H * 0.48), (W, H), (0, H)], fill=navy)
    d.polygon([(0, H * 0.60), (W, H * 0.46), (W, H * 0.48), (0, H * 0.62)], fill=red)
    tracked(d, (W * 0.06, H * 0.69), "VALTER", F("Bold", 220), cream, 0.05)
    tracked(d, (W * 0.06 + F("Bold", 220).getlength("VALTER") + 150, H * 0.735), "OIL", F("Bold", 160), (226, 62, 50), 0.05)
    tracked(d, (W * 0.065, H * 0.89), "MOTORÖL  ·  FOR ENGINES THAT MATTER  ·  SINCE 1958", F("Medium", 48), (190, 196, 214), 0.12)


def d_aurel(img, d, W, H):
    gold = (206, 172, 102)
    tracked(d, (W * 0.07, H * 0.30), "AUREL", F("Medium", 170), gold, 0.3)
    d.line([W * 0.085, H * 0.56, W * 0.42, H * 0.56], fill=gold, width=3)
    tracked(d, (W * 0.085, H * 0.60), "GENÈVE  ·  1887", F("Medium", 56), (220, 214, 200), 0.35)
    tracked(d, (W * 0.085, H * 0.80), "Precision, measured in tenths.", F("Medium", 60), (235, 232, 225), 0.02)


def d_ostra(img, d, W, H):
    teal = (10, 62, 70); gold = (232, 182, 52)
    d.rectangle([0, H * 0.78, W, H], fill=teal)
    d.rectangle([W * 0.06, H * 0.06, W * 0.06 + 310, H * 0.06 + 310], fill=gold)
    tracked(d, (W * 0.06 + 155, H * 0.06 + 40), "OSTRA", F("Bold", 110), teal, 0.04, "m")
    tracked(d, (W * 0.06 + 155, H * 0.06 + 160), "FILM", F("Bold", 110), teal, 0.3, "m")
    tracked(d, (W * 0.06, H * 0.815), "Farben, die bleiben.", F("SemiBold", 110), (245, 242, 232), 0.0)
    tracked(d, (W * 0.95, H * 0.85), "ISO 100  ·  36", F("Medium", 56), gold, 0.18, "r")


def d_halden(img, d, W, H):
    yellow = (244, 186, 44); black = (14, 14, 16)
    d.rectangle([0, H * 0.74, W, H], fill=black)
    d.rectangle([0, H * 0.74, W, H * 0.74 + 10], fill=yellow)
    tracked(d, (W * 0.05, H * 0.775), "HALDEN", F("Bold", 180), yellow, 0.06)
    tracked(d, (W * 0.05 + F("Bold", 180).getlength("HALDEN") + 140, H * 0.82), "TYRES", F("SemiBold", 120), (240, 240, 236), 0.2)
    tracked(d, (W * 0.95, H * 0.83), "Grip auf jedem Pass.", F("Medium", 70), (240, 240, 236), 0.0, "r")


def d_bergmann(img, d, W, H):
    red = (196, 28, 24); grey = (60, 64, 68)
    d.rectangle([W * 0.05, H * 0.07, W * 0.05 + 820, H * 0.07 + 250], fill=(250, 250, 248, 238))
    d.rectangle([W * 0.05, H * 0.07, W * 0.05 + 22, H * 0.07 + 250], fill=red)
    tracked(d, (W * 0.05 + 70, H * 0.07 + 18), "BERGMANN", F("Bold", 150), grey, 0.05)
    tracked(d, (W * 0.05 + 74, H * 0.07 + 178), "ALPENQUELLE  ·  MINERALWASSER", F("Medium", 44), red, 0.16)
    tracked(d, (W * 0.06, H * 0.84), "Frisch vom Gipfel.", F("Bold", 104), (255, 255, 255), 0.0)


BRANDS = [
    dict(name="MARZELLI", photo="ad_espresso_6.jpg", focus=(0.5, 0.35), draw=d_marzelli,
         grads=[((0, 0, 0), (0, 0, 0), 0.35, 0.0)]),
    dict(name="NORDLICHT", photo="ad_beer_3.jpg", focus=(0.25, 0.5), draw=d_nordlicht, grads=[]),
    dict(name="HELIOS BENZIN", photo="ad_alps_6.jpg", focus=(0.5, 0.6), draw=d_helios,
         grads=[((0, 0, 0), (0, 0, 0), 0.0, 0.55)]),
    dict(name="VALTER OIL", photo="ad_classic_7.jpg", focus=(0.5, 0.3), draw=d_valter, grads=[]),
    dict(name="AUREL WATCHES", photo="ad_watch_4.jpg", focus=(1.0, 0.5), draw=d_aurel,
         grads=[((0, 0, 0), (0, 0, 0), 0.85, 0.0, False)]),
    dict(name="OSTRA FILM", photo="ad_alps_5.jpg", focus=(0.5, 0.4), draw=d_ostra, grads=[]),
    dict(name="HALDEN TYRES", photo="ad_alps_8.jpg", focus=(0.5, 0.5), draw=d_halden, grads=[]),
    dict(name="BERGMANN", photo="ad_alps_4.jpg", focus=(0.5, 0.5), draw=d_bergmann,
         grads=[((0, 0, 0), (0, 0, 0), 0.0, 0.45)]),
]

# ---- road signs ----------------------------------------------------------------------------
SY = 2944  # signs region top
SIGNS = {  # name: (x, y, w, h) in atlas pixels
    "tri_fans": (0, SY, 512, 460),
    "tri_crest": (512, SY, 512, 460),
    "speed30": (1024, SY, 384, 384),
    "speed50": (1408, SY, 384, 384),
    "speed80": (1024, SY + 384, 384, 384),
    "plate_fans": (0, SY + 470, 500, 170),
    "plate_jump": (510, SY + 470, 500, 170),
    "village": (0, SY + 680, 900, 420),
    "chevron": (1024, SY + 780, 640, 320),
    "steel": (1792, SY, 256, 256),  # galvanised back of signs
    "frame": (1792, SY + 256, 256, 256),  # painted billboard frame / back panel
}
RED = (190, 22, 26); WHITE = (244, 244, 240); BLACK = (18, 18, 20); YEL = (246, 190, 30)


def retro(img, seed):
    """Reflective sheeting grain, faint fading, road grime from the bottom."""
    r = np.random.RandomState(seed)
    a = np.asarray(img).astype(np.float32) / 255.0
    h, w, _ = a.shape
    a *= (0.97 + 0.03 * r.rand(h, w))[..., None]
    g = np.linspace(1.0, 0.86, h)[:, None, None] ** 1.5
    a = a * g
    a = a * 0.95 + 0.03
    return Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8))


def person(d, cx, base, s, arms_up=True):
    """Pictogram figure (road-sign style), height ~ s."""
    d.ellipse([cx - s * 0.11, base - s, cx + s * 0.11, base - s * 0.78], fill=BLACK)
    d.polygon([(cx - s * 0.13, base - s * 0.74), (cx + s * 0.13, base - s * 0.74),
               (cx + s * 0.1, base - s * 0.36), (cx - s * 0.1, base - s * 0.36)], fill=BLACK)
    d.line([(cx - s * 0.06, base - s * 0.38), (cx - s * 0.14, base)], fill=BLACK, width=int(s * 0.1))
    d.line([(cx + s * 0.06, base - s * 0.38), (cx + s * 0.14, base)], fill=BLACK, width=int(s * 0.1))
    if arms_up:
        d.line([(cx - s * 0.1, base - s * 0.7), (cx - s * 0.3, base - s * 1.02)], fill=BLACK, width=int(s * 0.08))
        d.line([(cx + s * 0.1, base - s * 0.7), (cx + s * 0.3, base - s * 1.02)], fill=BLACK, width=int(s * 0.08))
    else:
        d.line([(cx - s * 0.12, base - s * 0.7), (cx - s * 0.2, base - s * 0.4)], fill=BLACK, width=int(s * 0.08))
        d.line([(cx + s * 0.12, base - s * 0.7), (cx + s * 0.2, base - s * 0.4)], fill=BLACK, width=int(s * 0.08))


def triangle(w, h, picto):
    S = 4; W, H = w * S, h * S
    im = Image.new("RGB", (W, H), (128, 130, 132))
    d = ImageDraw.Draw(im)
    m = W * 0.03
    outer = [(W / 2, m), (W - m, H - m), (m, H - m)]
    d.polygon(outer, fill=RED)
    k = 0.2
    cx, cy = W / 2, (m + 2 * (H - m)) / 3
    inner = [(cx + (x - cx) * (1 - k * 1.25), cy + (y - cy) * (1 - k * 1.25)) for x, y in outer]
    d.polygon(inner, fill=WHITE)
    picto(d, W, H)
    return im.resize((w, h), Image.LANCZOS)


def picto_fans(d, W, H):
    s = H * 0.30
    person(d, W * 0.40, H * 0.80, s * 0.92)
    person(d, W * 0.60, H * 0.80, s * 0.92, False)
    person(d, W * 0.50, H * 0.80, s)


def picto_crest(d, W, H):
    import math
    pts = []
    for i in range(41):
        x = W * 0.27 + W * 0.46 * i / 40
        y = H * 0.80 - math.sin(i / 40 * math.pi) ** 1.4 * H * 0.17
        pts.append((x, y))
    d.polygon(pts + [(W * 0.73, H * 0.83), (W * 0.27, H * 0.83)], fill=BLACK)
    # car leaping off the crest
    cx, cy = W * 0.52, H * 0.50
    d.rounded_rectangle([cx - W * 0.12, cy - H * 0.035, cx + W * 0.12, cy + H * 0.035], radius=H * 0.02, fill=BLACK)
    d.polygon([(cx - W * 0.06, cy - H * 0.03), (cx - W * 0.03, cy - H * 0.08), (cx + W * 0.05, cy - H * 0.08), (cx + W * 0.08, cy - H * 0.03)], fill=BLACK)
    for wx in (-0.075, 0.075):
        d.ellipse([cx + W * wx - H * 0.03, cy + H * 0.01, cx + W * wx + H * 0.03, cy + H * 0.07], fill=BLACK)


def speed(n, size):
    S = 4; W = size * S
    im = Image.new("RGB", (W, W), (128, 130, 132))
    d = ImageDraw.Draw(im)
    d.ellipse([W * 0.02, W * 0.02, W * 0.98, W * 0.98], fill=RED)
    d.ellipse([W * 0.14, W * 0.14, W * 0.86, W * 0.86], fill=WHITE)
    tracked(d, (W / 2, W * 0.18), str(n), F("Bold", int(W * 0.52)), BLACK, -0.02, "m")
    return im.resize((size, size), Image.LANCZOS)


def plate(w, h, lines, border=BLACK):
    S = 4; W, H = w * S, h * S
    im = Image.new("RGB", (W, H), WHITE)
    d = ImageDraw.Draw(im)
    d.rounded_rectangle([W * 0.02, H * 0.06, W * 0.98, H * 0.94], radius=H * 0.08, outline=border, width=int(H * 0.05))
    n = len(lines)
    for i, (txt, sz) in enumerate(lines):
        f = F("Bold", int(H * sz))
        while f.getlength(txt) * 1.05 > W * 0.86:
            f = F("Bold", int(f.size * 0.94))
        y = H * (0.5 + (i - (n - 1) / 2) * 0.42) - f.size * 0.62
        tracked(d, (W / 2, y), txt, f, BLACK, 0.04, "m")
    return im.resize((w, h), Image.LANCZOS)


def village(w, h):
    S = 4; W, H = w * S, h * S
    im = Image.new("RGB", (W, H), YEL)
    d = ImageDraw.Draw(im)
    d.rounded_rectangle([W * 0.02, H * 0.04, W * 0.98, H * 0.96], radius=H * 0.06, outline=BLACK, width=int(H * 0.035))
    tracked(d, (W / 2, H * 0.10), "SLOW", F("Bold", int(H * 0.40)), BLACK, 0.08, "m")
    d.line([W * 0.18, H * 0.62, W * 0.82, H * 0.62], fill=BLACK, width=int(H * 0.02))
    tracked(d, (W / 2, H * 0.66), "VILLAGE  ·  KINDER", F("SemiBold", int(H * 0.2)), BLACK, 0.1, "m")
    return im.resize((w, h), Image.LANCZOS)


def chevron(w, h):
    S = 4; W, H = w * S, h * S
    im = Image.new("RGB", (W, H), RED)
    d = ImageDraw.Draw(im)
    for k in range(3):
        x = W * (0.16 + k * 0.28)
        d.polygon([(x, H * 0.12), (x + W * 0.13, H * 0.12), (x + W * 0.27, H * 0.5), (x + W * 0.13, H * 0.88), (x, H * 0.88), (x + W * 0.14, H * 0.5)], fill=WHITE)
    return im.resize((w, h), Image.LANCZOS)


def main():
    atlas = Image.new("RGB", (2048, 4096), (120, 122, 124))
    for i, b in enumerate(BRANDS):
        p = weather(poster(b), i)
        atlas.paste(p, ((i % 2) * PW, (i // 2) * PH))
    parts = {
        "tri_fans": triangle(512, 460, picto_fans),
        "tri_crest": triangle(512, 460, picto_crest),
        "speed30": speed(30, 384), "speed50": speed(50, 384), "speed80": speed(80, 384),
        "plate_fans": plate(500, 170, [("CAUTION: FANS", 0.5)]),
        "plate_jump": plate(500, 170, [("CREST  ·  JUMP!", 0.5)]),
        "village": village(900, 420),
        "chevron": chevron(640, 320),
    }
    for k, im in parts.items():
        x, y, w, h = SIGNS[k]
        atlas.paste(retro(im, hash(k) % 1000), (x, y))
    steel = Image.open(os.path.join(ROOT, "assets/materials/steel/steel_diff.jpg")).convert("RGB").resize((256, 256))
    atlas.paste(steel, SIGNS["steel"][:2])
    frame = Image.open(os.path.join(ROOT, "assets/materials/painted_metal/painted_metal_diff.jpg")).convert("RGB").resize((256, 256))
    frame = ImageEnhance.Color(frame).enhance(0.3)
    atlas.paste(frame, SIGNS["frame"][:2])
    atlas.save(os.path.join(ROOT, "assets/gimmicks/gx_billboard.png"), optimize=True)
    print("ok")


if __name__ == "__main__":
    main()
