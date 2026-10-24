#!/usr/bin/env python3
"""Bakes the trackside texture atlases used by scripts/track/trackside_kit.gd.

  assets/trackside/trackside_paint.png  RGBA 2048x2176: graffiti (walls, piers)
                                        and fan messages painted on the tarmac
  assets/trackside/trackside_signs.png  RGB 2048x2176: banners, sponsor arches,
                                        warning signs, timing board, fan flags
  scripts/track/trackside_uv.gd         normalised Rect2 per region (generated)

Everything is original artwork drawn here; fonts in assets/trackside/src/fonts
(Permanent Marker, Rock Salt: Apache 2.0; Sedgwick Ave Display, Bungee: OFL 1.1).
Needs Pillow + numpy:  python3 -m venv /tmp/v && /tmp/v/bin/pip install pillow numpy
                       /tmp/v/bin/python tools/make_trackside_atlas.py
"""
import os, random
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageChops

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
FONTS = os.path.join(ROOT, "assets/trackside/src/fonts")
GAME_FONT = os.path.join(ROOT, "assets/fonts/BarlowSemiCondensed-Bold.ttf")
rnd = random.Random(7)


def font(name, size):
    path = GAME_FONT if name == "barlow" else os.path.join(FONTS, name)
    return ImageFont.truetype(path, size)


MARKER = "PermanentMarker-Regular.ttf"
SALT = "RockSalt-Regular.ttf"
SEDG = "SedgwickAveDisplay-Regular.ttf"
BUNG = "Bungee-Regular.ttf"


def noise(w, h, scale, seed):
    """Smooth value noise 0..1."""
    r = np.random.RandomState(seed)
    gw, gh = max(2, w // scale + 2), max(2, h // scale + 2)
    g = Image.fromarray((r.rand(gh, gw) * 255).astype(np.uint8))
    return np.asarray(g.resize((w, h), Image.BICUBIC), dtype=np.float32) / 255.0


def text_mask(text, fnt, pad=40, spacing=0):
    box = fnt.getbbox(text)
    w, h = box[2] - box[0] + pad * 2, box[3] - box[1] + pad * 2
    m = Image.new("L", (w, h), 0)
    ImageDraw.Draw(m).text((pad - box[0], pad - box[1]), text, font=fnt, fill=255)
    return m


def dilate(m, r):
    out = m
    while r > 0:
        k = min(r, 7)
        out = out.filter(ImageFilter.MaxFilter(k * 2 - 1 if k > 1 else 3))
        r -= k
    return out


def solid(size, col):
    return Image.new("RGBA", size, tuple(col) + (255,))


def gradient(size, top, bottom, mid=None):
    w, h = size
    t = np.linspace(0, 1, h)[:, None, None]
    a, b = np.array(top, np.float32), np.array(bottom, np.float32)
    if mid is not None:
        c = np.array(mid, np.float32)
        g = np.where(t < 0.5, a + (c - a) * (t * 2), c + (b - c) * (t * 2 - 1))
    else:
        g = a + (b - a) * t
    g = np.broadcast_to(g, (h, w, 3)).astype(np.uint8)
    return Image.fromarray(np.dstack([g, np.full((h, w), 255, np.uint8)]), "RGBA")


def paste_mask(dst, col_img, mask):
    dst.alpha_composite(Image.composite(col_img, Image.new("RGBA", dst.size, (0, 0, 0, 0)), mask))


def weather(img, seed, fade=0.25, scale=24):
    """Sun-faded, slightly patchy spray paint on rough concrete."""
    a = np.asarray(img, np.float32).copy()
    n1 = noise(img.width, img.height, scale, seed)
    n2 = np.random.RandomState(seed + 1).rand(img.height, img.width).astype(np.float32)
    a[..., 3] *= np.clip(1.0 - fade * n1 - 0.18 * (n2 > 0.93), 0, 1)
    a[..., :3] = a[..., :3] * (0.9 + 0.1 * n1[..., None])
    return Image.fromarray(a.clip(0, 255).astype(np.uint8), "RGBA")


def drips(mask, img, col, count, seed, max_len=60):
    r = random.Random(seed)
    m = np.asarray(mask) > 128
    ys, xs = np.nonzero(m)
    if len(xs) == 0:
        return
    d = ImageDraw.Draw(img)
    for _ in range(count):
        k = r.randrange(len(xs))
        x, y = xs[k], ys[k]
        while y + 1 < m.shape[0] and m[y + 1, x]:
            y += 1
        ln = r.randint(8, max_len)
        wd = r.choice([2, 3, 3, 4])
        d.line([(x, y), (x, y + ln)], fill=tuple(col) + (230,), width=wd)
        d.ellipse([x - wd * 0.7, y + ln - wd * 0.7, x + wd * 0.7, y + ln + wd * 0.7], fill=tuple(col) + (230,))


def piece(text, fname, size, fill_top, fill_bot, outline, shadow, cloud=None, fill_mid=None, seed=1, skew=0.18,
          extrude=(10, 9), outline_w=7, highlight=True):
    """A wall 'piece': gradient fill, highlight, outline, 3D block shadow, optional cloud backdrop, drips."""
    fnt = font(fname, size)
    m = text_mask(text, fnt, pad=70)
    # lean the letters a little, like a hand-styled piece
    m = m.transform(m.size, Image.AFFINE, (1, skew, -skew * m.height * 0.5, 0, 1, 0), Image.BICUBIC)
    m = dilate(m, 2).filter(ImageFilter.GaussianBlur(1.2)).point(lambda v: 255 if v > 110 else 0)
    w, h = m.size
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    out = dilate(m, outline_w)
    if cloud is not None:
        cl = dilate(out, 16).filter(ImageFilter.GaussianBlur(8)).point(lambda v: 255 if v > 90 else 0)
        paste_mask(img, solid((w, h), cloud), cl)
        cl_line = ImageChops.subtract(dilate(cl, 3), cl)
        paste_mask(img, solid((w, h), outline), cl_line)
    ex = Image.new("L", (w, h), 0)
    for k in range(extrude[0]):
        ex = ImageChops.lighter(ex, ImageChops.offset(out, k + 1, int((k + 1) * extrude[1] / extrude[0])))
    paste_mask(img, solid((w, h), shadow), ex)
    paste_mask(img, solid((w, h), outline), out)
    paste_mask(img, gradient((w, h), fill_top, fill_bot, fill_mid), m)
    if highlight:
        # white highlight strokes on the upper-left of each letter
        hi = ImageChops.subtract(m, ImageChops.offset(m, 5, 5))
        hi = hi.filter(ImageFilter.GaussianBlur(1)).point(lambda v: 210 if v > 120 else 0)
        paste_mask(img, solid((w, h), (250, 250, 245)), hi)
    drips(out, img, outline, 7, seed, 50)
    soft = img.filter(ImageFilter.GaussianBlur(0.8)) # overspray
    return weather(soft, seed)


def tag(text, fname, size, col, seed=3, rot=-6):
    fnt = font(fname, size)
    m = text_mask(text, fnt, pad=30).rotate(rot, Image.BICUBIC, expand=True)
    img = Image.new("RGBA", m.size, (0, 0, 0, 0))
    paste_mask(img, solid(m.size, col), m)
    drips(m, img, col, 4, seed, 34)
    return weather(img.filter(ImageFilter.GaussianBlur(0.6)), seed, 0.15)


def throwup(text, size, fill, outline, seed=5):
    """Quick bubble letters: silver or white fill, thick black line."""
    fnt = font(BUNG, size)
    m = text_mask(text, fnt, pad=50)
    m = dilate(m, 4).filter(ImageFilter.GaussianBlur(5)).point(lambda v: 255 if v > 120 else 0)
    m = m.rotate(rnd.uniform(-4, 4), Image.BICUBIC)
    img = Image.new("RGBA", m.size, (0, 0, 0, 0))
    paste_mask(img, solid(m.size, outline), dilate(m, 6))
    paste_mask(img, solid(m.size, fill), m)
    inner = ImageChops.subtract(m, dilate(ImageChops.invert(m), 9).point(lambda v: 255 - v))
    drips(m, img, fill, 5, seed, 40)
    return weather(img.filter(ImageFilter.GaussianBlur(0.9)), seed, 0.3)


def stencil(text, size, col, seed=9):
    fnt = font(BUNG, size)
    m = text_mask(text, fnt, pad=24)
    a = np.asarray(m).copy()
    # stencil bridges: thin vertical gaps through the letters
    for x in range(0, a.shape[1], int(size * 0.62)):
        a[:, x:x + max(2, size // 22)] = 0
    m = Image.fromarray(a)
    img = Image.new("RGBA", m.size, (0, 0, 0, 0))
    paste_mask(img, solid(m.size, col), m)
    halo = m.filter(ImageFilter.GaussianBlur(6)).point(lambda v: int(v * 0.25))
    paste_mask(img, solid(m.size, col), halo)
    return weather(img, seed, 0.2)


def road_word(text, size, seed, fname=MARKER):
    """Fan message hand-rolled on the tarmac in white road paint (tinted per use)."""
    fnt = font(fname, size)
    m = text_mask(text, fnt, pad=26)
    m = dilate(m, 3)
    w, h = m.size
    a = np.asarray(m, np.float32) / 255.0
    n1 = noise(w, h, 6, seed)
    n2 = noise(w, h, 40, seed + 3)
    # brush texture: streaky, worn by tyres in the middle
    streak = noise(w, h, 3, seed + 7)
    alpha = a * np.clip(0.95 - 0.35 * (n1 > 0.72) - 0.25 * n2 * (streak > 0.6), 0, 1)
    rgb = np.full((h, w, 3), 235, np.float32) * (0.92 + 0.08 * n1[..., None])
    img = Image.fromarray(np.dstack([rgb, alpha * 255]).clip(0, 255).astype(np.uint8), "RGBA")
    return img.filter(ImageFilter.GaussianBlur(0.7))


def road_symbol(kind, size, seed):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    s = size
    if kind == "arrow": # chevron pointing forward (up)
        for k in range(3):
            y = s * (0.18 + k * 0.24)
            d.line([(s * 0.12, y + s * 0.2), (s * 0.5, y), (s * 0.88, y + s * 0.2)], fill=(235, 235, 235, 255), width=int(s * 0.07))
    elif kind == "heart":
        d.ellipse([s * 0.12, s * 0.2, s * 0.52, s * 0.58], fill=(235, 235, 235, 255))
        d.ellipse([s * 0.48, s * 0.2, s * 0.88, s * 0.58], fill=(235, 235, 235, 255))
        d.polygon([(s * 0.14, s * 0.45), (s * 0.86, s * 0.45), (s * 0.5, s * 0.88)], fill=(235, 235, 235, 255))
    elif kind == "check": # chequered square
        c = 6
        for i in range(c):
            for j in range(c):
                if (i + j) % 2 == 0:
                    d.rectangle([s * i / c, s * j / c, s * (i + 1) / c - 1, s * (j + 1) / c - 1], fill=(235, 235, 235, 255))
    a = np.asarray(img, np.float32)
    n1 = noise(s, s, 6, seed)
    a[..., 3] *= np.clip(1.05 - 0.4 * (n1 > 0.7), 0, 1)
    return Image.fromarray(a.clip(0, 255).astype(np.uint8), "RGBA").filter(ImageFilter.GaussianBlur(0.8))


# ------------------------------------------------------------------ signs (opaque)

def panel(size, bg, text, ink, fname="barlow", fsize=None, accent=None, border=None, sub=None, sub_ink=None):
    w, h = size
    img = Image.new("RGB", size, bg)
    d = ImageDraw.Draw(img)
    if accent:
        d.rectangle([0, h - h * 0.16, w, h], fill=accent)
        d.rectangle([0, 0, w, h * 0.06], fill=accent)
    if border:
        bw = max(4, h // 18)
        d.rectangle([bw, bw, w - bw - 1, h - bw - 1], outline=border, width=bw)
    fs = fsize or int(h * (0.52 if sub is None else 0.42))
    f = font(fname, fs)
    while f.getlength(text) > w * 0.9 and fs > 8:
        fs -= 2
        f = font(fname, fs)
    cy = h * (0.46 if sub is None else 0.36)
    d.text((w / 2, cy), text, font=f, fill=ink, anchor="mm")
    if sub:
        f2 = font("barlow", int(h * 0.2))
        d.text((w / 2, h * 0.74), sub, font=f2, fill=sub_ink or ink, anchor="mm")
    return img


def warning(size, text, sub=None, icon="!", yellow=True):
    """Triangle warning sign on a white plate with text below."""
    w, h = size
    img = Image.new("RGB", size, (236, 234, 226) if yellow else (230, 230, 228))
    d = ImageDraw.Draw(img)
    cx, top, side = w / 2, h * 0.06, h * 0.52
    tri = [(cx, top), (cx - side * 0.58, top + side), (cx + side * 0.58, top + side)]
    d.polygon(tri, fill=(196, 28, 22))
    inner = [(cx, top + side * 0.2), (cx - side * 0.42, top + side * 0.86), (cx + side * 0.42, top + side * 0.86)]
    d.polygon(inner, fill=(248, 246, 240))
    if icon == "!":
        d.rectangle([cx - side * 0.04, top + side * 0.36, cx + side * 0.04, top + side * 0.66], fill=(20, 20, 20))
        d.ellipse([cx - side * 0.05, top + side * 0.71, cx + side * 0.05, top + side * 0.8], fill=(20, 20, 20))
    elif icon == "car": # car skidding off
        d.rounded_rectangle([cx - side * 0.2, top + side * 0.5, cx + side * 0.2, top + side * 0.66], 6, fill=(20, 20, 20))
        d.rounded_rectangle([cx - side * 0.11, top + side * 0.41, cx + side * 0.1, top + side * 0.53], 5, fill=(20, 20, 20))
        for sx in (-1, 1):
            d.line([(cx + sx * side * 0.06, top + side * 0.7), (cx + sx * side * 0.16, top + side * 0.82)], fill=(20, 20, 20), width=5)
    elif icon == "cow":
        d.ellipse([cx - side * 0.2, top + side * 0.46, cx + side * 0.14, top + side * 0.66], fill=(20, 20, 20))
        d.ellipse([cx + side * 0.1, top + side * 0.42, cx + side * 0.24, top + side * 0.54], fill=(20, 20, 20))
        for lx in (-0.15, -0.06, 0.03, 0.1):
            d.rectangle([cx + side * lx, top + side * 0.62, cx + side * (lx + 0.03), top + side * 0.78], fill=(20, 20, 20))
    elif icon == "deer":
        d.ellipse([cx - side * 0.18, top + side * 0.48, cx + side * 0.12, top + side * 0.62], fill=(20, 20, 20))
        d.line([(cx + side * 0.1, top + side * 0.5), (cx + side * 0.18, top + side * 0.36)], fill=(20, 20, 20), width=7)
        d.line([(cx + side * 0.18, top + side * 0.36), (cx + side * 0.12, top + side * 0.27)], fill=(20, 20, 20), width=4)
        d.line([(cx + side * 0.18, top + side * 0.36), (cx + side * 0.25, top + side * 0.28)], fill=(20, 20, 20), width=4)
        for lx in (-0.15, -0.08, 0.04, 0.09):
            d.line([(cx + side * lx, top + side * 0.6), (cx + side * lx, top + side * 0.8)], fill=(20, 20, 20), width=4)
    elif icon == "snow":
        for a in range(3):
            import math
            ang = a * math.pi / 3
            dx, dy = math.cos(ang) * side * 0.2, math.sin(ang) * side * 0.2
            d.line([(cx - dx, top + side * 0.6 - dy), (cx + dx, top + side * 0.6 + dy)], fill=(20, 20, 20), width=6)
    def fit(t, fs):
        f = font("barlow", fs)
        while f.getlength(t) > w * 0.9 and fs > 8:
            fs -= 1
            f = font("barlow", fs)
        return f
    d.text((cx, h * 0.72), text, font=fit(text, int(h * 0.15)), fill=(20, 20, 20), anchor="mm")
    if sub:
        d.text((cx, h * 0.88), sub, font=fit(sub, int(h * 0.1)), fill=(40, 40, 40), anchor="mm")
    d.rectangle([2, 2, w - 3, h - 3], outline=(30, 30, 30), width=4)
    return img


def fan_sheet(size, text, ink, seed, sub=None):
    """Hand-painted bedsheet banner."""
    w, h = size
    a = np.full((h, w, 3), (232, 228, 214), np.float32) * (0.9 + 0.1 * noise(w, h, 30, seed)[..., None])
    img = Image.fromarray(a.astype(np.uint8), "RGB")
    d = ImageDraw.Draw(img)
    fs = int(h * (0.5 if sub is None else 0.42))
    f = font(MARKER, fs)
    while f.getlength(text) > w * 0.92:
        fs -= 2
        f = font(MARKER, fs)
    d.text((w / 2 + rnd.uniform(-8, 8), h * (0.45 if sub is None else 0.38)), text, font=f, fill=ink, anchor="mm")
    if sub:
        d.text((w / 2, h * 0.78), sub, font=font(MARKER, int(h * 0.2)), fill=ink, anchor="mm")
    return img


def timing_board(size):
    w, h = size
    img = Image.new("RGB", size, (14, 15, 16))
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, w, h * 0.16], fill=(170, 24, 20))
    d.text((w / 2, h * 0.08), "STAGE TIMES  •  ZEITEN", font=font("barlow", int(h * 0.11)), fill=(245, 240, 230), anchor="mm")
    rows = [("1", "K. WEBER", "1:24.61"), ("2", "J. LINDQVIST", "+0.84"), ("3", "A. ROSSI", "+1.37"),
            ("4", "M. DUVAL", "+2.05"), ("5", "P. NOVAK", "+3.92"), ("6", "S. BRENNAN", "+4.40")]
    f = font("barlow", int(h * 0.1))
    for k, (p, nm, t) in enumerate(rows):
        y = h * (0.27 + k * 0.125)
        d.text((w * 0.06, y), p, font=f, fill=(255, 196, 40), anchor="lm")
        d.text((w * 0.15, y), nm, font=f, fill=(255, 196, 40), anchor="lm")
        d.text((w * 0.94, y), t, font=f, fill=(255, 196, 40), anchor="rm")
    return img


def flag_img(size, kind):
    w, h = size
    img = Image.new("RGB", size, (240, 240, 240))
    d = ImageDraw.Draw(img)
    tri_v = {"it": [(0, 146, 70), (244, 245, 240), (206, 43, 55)], "fr": [(0, 35, 149), (244, 245, 240), (237, 41, 57)],
             "ro": [(0, 43, 127), (252, 209, 22), (206, 17, 38)], "be": [(20, 20, 20), (253, 218, 36), (239, 51, 64)],
             "ie": [(22, 155, 98), (244, 245, 240), (255, 136, 62)]}
    tri_h = {"de": [(20, 20, 20), (221, 0, 0), (255, 206, 0)], "at": [(237, 41, 57), (244, 245, 240), (237, 41, 57)],
             "nl": [(174, 28, 40), (244, 245, 240), (33, 70, 139)], "hu": [(205, 42, 62), (244, 245, 240), (67, 111, 77)],
             "ee": [(0, 114, 206), (20, 20, 20), (244, 245, 240)]}
    if kind in tri_v:
        for k, c in enumerate(tri_v[kind]):
            d.rectangle([w * k / 3, 0, w * (k + 1) / 3, h], fill=c)
    elif kind in tri_h:
        for k, c in enumerate(tri_h[kind]):
            d.rectangle([0, h * k / 3, w, h * (k + 1) / 3], fill=c)
    elif kind in ("fi", "se", "no", "dk"):
        bg, cr = {"fi": ((244, 245, 240), (0, 47, 108)), "se": ((0, 106, 167), (254, 204, 0)),
                  "no": ((186, 12, 47), (244, 245, 240)), "dk": ((200, 16, 46), (244, 245, 240))}[kind]
        d.rectangle([0, 0, w, h], fill=bg)
        d.rectangle([w * 0.3, 0, w * 0.42, h], fill=cr)
        d.rectangle([0, h * 0.42, w, h * 0.58], fill=cr)
        if kind == "no":
            d.rectangle([w * 0.33, 0, w * 0.39, h], fill=(0, 32, 91))
            d.rectangle([0, h * 0.46, w, h * 0.54], fill=(0, 32, 91))
    elif kind == "pl":
        d.rectangle([0, h / 2, w, h], fill=(220, 20, 60))
    elif kind == "cz":
        d.rectangle([0, h / 2, w, h], fill=(215, 20, 26))
        d.polygon([(0, 0), (w * 0.5, h / 2), (0, h)], fill=(17, 69, 126))
    elif kind == "ch":
        d.rectangle([0, 0, w, h], fill=(218, 41, 28))
        d.rectangle([w * 0.42, h * 0.2, w * 0.58, h * 0.8], fill=(255, 255, 255))
        d.rectangle([w * 0.3, h * 0.4, w * 0.7, h * 0.6], fill=(255, 255, 255))
    elif kind == "chk": # chequered
        c = 8
        for i in range(c):
            for j in range(5):
                if (i + j) % 2 == 0:
                    d.rectangle([w * i / c, h * j / 5, w * (i + 1) / c, h * (j + 1) / 5], fill=(20, 20, 20))
    elif kind == "fan": # fan-club flag
        d.rectangle([0, 0, w, h], fill=(24, 44, 92))
        d.text((w / 2, h / 2), "FAN CLUB", font=font("barlow", int(h * 0.3)), fill=(250, 210, 60), anchor="mm")
    return img


# ------------------------------------------------------------------ packing

class Packer:
    def __init__(self, w, h, mode):
        self.img = Image.new(mode, (w, h), (0, 0, 0, 0) if mode == "RGBA" else (128, 128, 128))
        self.w, self.h = w, h
        self.x = self.y = self.row = 0
        self.regions = {}
        self.items = []

    def add(self, key, im, max_w=None, max_h=None):
        if max_w and im.width > max_w:
            im = im.resize((max_w, int(im.height * max_w / im.width)), Image.LANCZOS)
        if max_h and im.height > max_h:
            im = im.resize((int(im.width * max_h / im.height), max_h), Image.LANCZOS)
        self.items.append((key, im))

    def pack(self):
        """Shelf packing, tallest first."""
        pad = 4
        for key, im in sorted(self.items, key=lambda kv: -kv[1].height):
            if self.x + im.width + pad > self.w:
                self.x = 0
                self.y += self.row + pad
                self.row = 0
            if self.y + im.height > self.h:
                raise RuntimeError("atlas full at " + key)
            if im.mode == "RGBA" and self.img.mode == "RGBA":
                self.img.alpha_composite(im, (self.x, self.y))
            else:
                self.img.paste(im.convert(self.img.mode), (self.x, self.y))
            self.regions[key] = (self.x / self.w, self.y / self.h, im.width / self.w, im.height / self.h, im.width / im.height)
            self.x += im.width + pad
            self.row = max(self.row, im.height)


def main():
    paint = Packer(2048, 2176, "RGBA")
    # --- graffiti pieces (wall art), all original
    P = paint
    P.add("g_vollgas", piece("VOLLGAS", SEDG, 210, (255, 120, 40), (190, 20, 60), (18, 18, 22), (40, 30, 90),
                             cloud=(235, 235, 240), fill_mid=(255, 210, 60), seed=11), max_w=1000, max_h=270)
    P.add("g_apex", piece("APEX", BUNG, 200, (60, 220, 200), (20, 80, 170), (14, 14, 20), (230, 60, 120), seed=12,
                          cloud=(30, 30, 36)), max_w=1000, max_h=270)
    P.add("g_nolift", piece("NO LIFT", SEDG, 190, (250, 250, 250), (150, 160, 175), (190, 25, 30), (20, 20, 24),
                            fill_mid=(205, 215, 225), seed=13), max_w=1000, max_h=250)
    P.add("g_kurve", piece("KURVE", BUNG, 180, (150, 230, 70), (20, 120, 60), (16, 16, 16), (250, 200, 40), seed=14,
                           cloud=(245, 245, 230)), max_w=1000, max_h=250)
    P.add("g_slip", piece("SLIPSTREAM", SEDG, 170, (120, 190, 255), (90, 40, 200), (12, 12, 18), (255, 255, 255),
                          fill_mid=(220, 120, 255), seed=15), max_w=1000, max_h=240)
    P.add("g_flat", piece("FLAT OUT", BUNG, 150, (255, 230, 60), (240, 110, 20), (25, 20, 18), (120, 20, 20), seed=16),
          max_w=1000, max_h=240)
    for key, txt, col in [("t_kaos", "kaos", (20, 20, 20)), ("t_mira", "Mira 07", (200, 30, 40)),
                          ("t_brk", "BRK crew", (30, 60, 170)), ("t_toxa", "toxa", (240, 240, 240)),
                          ("t_zone", "zone7", (20, 20, 20)), ("t_lupo", "LUPO!", (230, 120, 20))]:
        P.add(key, tag(txt, SEDG if key != "t_brk" else SALT, 120, col, seed=hash(key) & 255), max_w=480, max_h=200)
    for key, txt, f, o in [("u_rx", "RX", (215, 220, 228), (12, 12, 14)), ("u_gt", "GT", (250, 250, 250), (20, 20, 120)),
                           ("u_om", "OMG", (255, 214, 0), (12, 12, 12))]:
        P.add(key, throwup(txt, 190, f, o, seed=len(key) * 31), max_w=520, max_h=260)
    P.add("s_norace", stencil("NO RACING ON PUBLIC ROADS", 64, (24, 24, 24)), max_w=1000)
    P.add("s_brake", stencil("BRAKE LATE", 90, (170, 20, 20)), max_w=700)
    # --- road paint (white, tinted by vertex colour)
    words = ["GO!", "GO GO GO", "ALLEZ!", "VAI!", "FORZA", "HOPP HOPP", "VAMOS", "HAJRÁ", "HAI!", "WEBER", "ROSSI",
             "LINDQVIST", "DUVAL", "NOVAK", "BRENNAN", "HAAS", "MANCINI", "KOWALSKI", "MOREAU", "SØRENSEN", "CASTELL",
             "FLAT OUT", "NO LIFT", "SEND IT"]
    for k, wd in enumerate(words):
        P.add("r_" + wd, road_word(wd, 110, 100 + k), max_w=700, max_h=140)
    for k, s in enumerate(["arrow", "heart", "check"]):
        P.add("r_sym_" + s, road_symbol(s, 160, 300 + k))
    paint.pack()
    paint.img.save(os.path.join(ROOT, "assets/trackside/trackside_paint.png"))

    signs = Packer(2048, 2176, "RGB")
    S = signs
    # fence banners 8:1
    for key, txt, bg, ink, acc in [
        ("b_helios", "HELIOS BENZIN", (230, 220, 190), (16, 16, 16), (205, 90, 20)),
        ("b_valter", "VALTER OIL", (20, 30, 64), (235, 225, 200), (160, 25, 20)),
        ("b_kronen", "KRONEN REIFEN", (14, 14, 14), (250, 196, 40), (250, 196, 40)),
        ("b_nordlicht", "NORDLICHT BIER", (18, 52, 34), (240, 240, 230), (190, 160, 64)),
        ("b_aurel", "AUREL WATCHES", (8, 8, 8), (205, 170, 92), (205, 170, 92)),
        ("b_rallye", "SLIPSTREAM RALLYE", (200, 24, 20), (250, 250, 250), (20, 20, 20)),
        ("b_falke", "KAFFEE FALKE", (88, 42, 24), (245, 225, 180), (245, 225, 180)),
        ("b_marzelli", "MARZELLI", (88, 16, 18), (238, 225, 200), (238, 225, 200)),
        ("b_spect", "SPECTATOR AREA  •  ZUSCHAUER", (16, 120, 60), (250, 250, 250), (250, 250, 250)),
        ("b_press", "TV  •  PRESS  •  MEDIA", (240, 240, 236), (24, 24, 30), (24, 90, 190)),
    ]:
        S.add(key, panel((1016, 127), bg, txt, ink, accent=acc))
    # arch / gantry headers 6:1
    for key, txt, bg, ink, sub in [("a_start", "START  •  FINISH", (200, 24, 20), (255, 255, 255), "SLIPSTREAM RALLYE"),
                                   ("a_helios", "HELIOS", (240, 120, 20), (255, 255, 255), "BENZIN • OEL • SERVICE"),
                                   ("a_kronen", "KRONEN", (14, 14, 14), (250, 196, 40), "REIFEN FÜR SIEGER"),
                                   ("a_valter", "VALTER", (20, 30, 64), (240, 230, 210), "MOTOR OIL"),
                                   ("a_stage", "STAGE 7", (18, 18, 20), (255, 255, 255), "SPECTATOR STAGE")]:
        S.add(key, panel((768, 128), bg, txt, ink, fname=BUNG if key != "a_start" else "barlow", sub=sub, accent=None))
    # warning and fun signs 4:5
    for key, txt, sub, icon in [("w_spect", "ZUSCHAUER", "HINTER DAS BAND!", "!"),
                                ("w_flying", "FLYING CARS", "NEXT 2 KM", "car"),
                                ("w_cows", "MOOR CATTLE", "AND DRIVERS", "cow"),
                                ("w_deer", "WILDWECHSEL", "WATCH FOR DEER", "deer"),
                                ("w_snow", "GLATTEIS", "YOUR TYRES: NO", "snow"),
                                ("w_kurve", "ACHTUNG", "KURVE • BRAKE!", "car"),
                                ("w_noparking", "NO SPECTATORS", "BEYOND THIS POINT", "!")]:
        S.add(key, warning((200, 250), txt, sub, icon))
    for key, txt, ink, sub in [("f_weber", "WEBER WE LOVE YOU!", (190, 20, 20), None),
                               ("f_rossi", "FORZA ROSSI", (20, 110, 40), "FAN CLUB VALTELLINA"),
                               ("f_lind", "LINDQVIST FLAT OUT", (20, 50, 150), None),
                               ("f_hopp", "HOPP HOPP HOPP!", (20, 20, 20), None),
                               ("f_novak", "NOVAK! JEDEME!", (200, 30, 30), None),
                               ("f_duval", "ALLEZ DUVAL", (30, 40, 140), "CORNER 3 FAN CLUB")]:
        S.add(key, fan_sheet((672, 168), txt, ink, hash(key) & 255, sub))
    S.add("timing", timing_board((512, 320)))
    for k in ["de", "it", "fr", "ro", "at", "fi", "se", "pl", "cz", "nl", "be", "ch", "no", "hu", "ee", "ie", "dk", "chk", "fan"]:
        S.add("flag_" + k, flag_img((150, 100), k))
    # plain plates
    S.add("p_town", panel((504, 126), (196, 186, 166), "PORTA VECCHIA  •  1514", (70, 60, 50), border=(150, 140, 120)))
    S.add("p_barn", panel((504, 126), (120, 40, 30), "HOF BRANDNER", (240, 228, 200)))
    S.add("p_gallery", panel((504, 126), (220, 220, 216), "LAWINENGALERIE  SCHNEEKOPF", (30, 30, 30), border=(40, 40, 40)))
    S.add("p_rail", panel((504, 126), (40, 40, 44), "MOORBAHN 1887", (220, 210, 190)))
    S.add("p_kronen", panel((1016, 160), (14, 14, 14), "KRONEN", (250, 196, 40), fname=BUNG, sub="REIFEN • TYRES • PNEUMATICI"))
    S.add("p_coast", panel((504, 126), (236, 230, 214), "BELVEDERE", (40, 70, 110), border=(40, 70, 110)))
    signs.pack()
    signs.img.save(os.path.join(ROOT, "assets/trackside/trackside_signs.png"))

    with open(os.path.join(ROOT, "scripts/track/trackside_uv.gd"), "w") as f:
        f.write("class_name TracksideUV\nextends RefCounted\n## GENERATED by tools/make_trackside_atlas.py - do not edit.\n")
        f.write("## Normalised [x, y, w, h, aspect w/h] per atlas region.\n\n")
        for name, pk in (("PAINT", paint), ("SIGNS", signs)):
            f.write("const %s := {\n" % name)
            for k, r in pk.regions.items():
                f.write('\t"%s": [%.6f, %.6f, %.6f, %.6f, %.4f],\n' % (k, *r))
            f.write("}\n\n")
    print("paint", len(paint.regions), "signs", len(signs.regions), "rows used", paint.y + paint.row, signs.y + signs.row)


main()
