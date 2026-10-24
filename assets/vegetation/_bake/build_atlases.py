"""Builds the vegetation texture atlases for race_game from baked renders
(Poly Haven CC0 models) and ambientCG CC0 leaf/bark scans."""
import json, math, random, sys, os
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

S = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.dirname(S) # assets/vegetation
random.seed(7)
np.random.seed(7)


def dilate(img: Image.Image) -> Image.Image:
    """Push-pull fill of the colour under transparent pixels so mipmaps don't
    bleed dark fringes. Keeps alpha untouched."""
    a = np.asarray(img).astype(np.float32) / 255.0
    rgb, al = a[..., :3], a[..., 3:4]
    w = (al > 0.02).astype(np.float32)
    levels = [(rgb * w, w)]
    while levels[-1][1].shape[0] > 1 and levels[-1][1].shape[1] > 1:
        c, ww = levels[-1]
        h2, w2 = c.shape[0] // 2, c.shape[1] // 2
        c = c[:h2 * 2, :w2 * 2].reshape(h2, 2, w2, 2, 3).sum((1, 3))
        ww = ww[:h2 * 2, :w2 * 2].reshape(h2, 2, w2, 2, 1).sum((1, 3))
        levels.append((c, ww))
    fill = levels[-1][0] / np.maximum(levels[-1][1], 1e-6)
    for c, ww in reversed(levels[:-1]):
        up = np.repeat(np.repeat(fill, 2, 0), 2, 1)
        up = np.pad(up, ((0, c.shape[0] - up.shape[0]), (0, c.shape[1] - up.shape[1]), (0, 0)), mode='edge')
        own = c / np.maximum(ww, 1e-6)
        k = np.clip(ww, 0, 1)
        fill = own * k + up * (1 - k)
    out = np.concatenate([fill, al], -1)
    return Image.fromarray((np.clip(out, 0, 1) * 255).astype(np.uint8), 'RGBA')


def load_cell(path, px):
    im = Image.open(path).convert('RGBA')
    return im.resize((px, px), Image.LANCZOS)


def flat_normal(size):
    return Image.new('RGBA', size, (128, 128, 255, 255))


# ------------------------------------------------------------------ grass atlas
def grass():
    b = S + '/bake1/'
    info = json.load(open(b + 'info.json'))
    names = [
        'grass_medium_01__grass_medium_01_large_a_LOD0__y0', 'grass_medium_01__grass_medium_01_large_b_LOD0__y0',
        'grass_medium_01__grass_medium_01_large_c_LOD0__y0', 'grass_medium_01__grass_medium_01_mid_a_LOD0__y0',
        'grass_medium_01__grass_medium_01_mid_b_LOD0__y0', 'grass_medium_01__grass_medium_01_mid_c_LOD0__y0',
        'grass_medium_01__grass_medium_01_small_a_LOD0__y0', 'grass_medium_01__grass_medium_01_tall_a_LOD0__y0',
        'grass_medium_01__grass_medium_01_tall_b_LOD0__y0', 'grass_medium_02__grass_medium_02_c__y0',
        'grass_medium_02__grass_medium_02_d__y0', 'grass_medium_02__grass_medium_02_e__y0',
        'grass_medium_01__grass_medium_01_large_a_LOD0__y90', 'grass_medium_01__grass_medium_01_large_b_LOD0__y90',
        'grass_medium_01__grass_medium_01_mid_a_LOD0__y90', 'grass_medium_02__grass_medium_02_e__y90',
        # flowers & weeds (index 16..)
        'dandelion_01__dandelion_01_a_LOD0__y0', 'dandelion_01__dandelion_01_b_LOD0__y0',
        'dandelion_01__dandelion_01_c_LOD0__y0', 'celandine_01__celandine_01_c_LOD0__y0',
        'celandine_01__celandine_01_d_LOD0__y0', 'shrub_03__shrub_03_b__y0',
        'shrub_03__shrub_03_a__y0', 'weed_plant_02__weed_plant_02_a_LOD0__y0',
        # forest floor (index 24..)
        'fern_02__fern_02_a__y0', 'fern_02__fern_02_b__y0', 'fern_02__fern_02_c__y0', 'fern_02__fern_02_d__y0',
        'nettle_plant__nettle_plant_medium_a_LOD0__y0', 'nettle_plant__nettle_plant_tall_a_LOD0__y0',
        'fern_02__fern_02_b__y90', 'fern_02__fern_02_c__y90',
    ]
    cols, rows, px = 8, 4, 512
    atlas = Image.new('RGBA', (cols * px, rows * px), (0, 0, 0, 0))
    sizes = []
    for i, n in enumerate(names):
        cell = load_cell(b + n + '_p0_albedo.png', px)
        if i in (9, 10, 11, 15):  # the dry scans are very pale next to the lush ones
            arr = np.asarray(cell).astype(np.float32)
            arr[..., :3] *= np.array([0.72, 0.74, 0.62])
            cell = Image.fromarray(arr.clip(0, 255).astype(np.uint8), 'RGBA')
        atlas.paste(cell, ((i % cols) * px, (i // cols) * px))
        sizes.append(round(info[n + '_p0']['width_m'], 3))
    os.makedirs(OUT + '/grass', exist_ok=True)
    dilate(atlas).save(OUT + '/grass/grass_atlas.png')
    return {'cols': cols, 'rows': rows, 'sizes': sizes}


# ------------------------------------------------------------------ conifer atlas
def conifer():
    b = S + '/bake2/'
    side = json.load(open(b + 'info_side.json'))
    top = json.load(open(b + 'info.json'))
    names = [
        ('fir_sapling__fir_sapling_a__y0_p90', top), ('fir_sapling__fir_sapling_b__y0_p90', top),
        ('fir_sapling__fir_sapling_c__y0_p90', top), ('pine_sapling_small__pine_sapling_small_a__y0_p90', top),
        ('pine_sapling_small__pine_sapling_small_b__y0_p90', top), ('pine_sapling_small__pine_sapling_small_c__y0_p90', top),
        ('fir_sapling__fir_sapling_a__y0_p0', side), ('fir_sapling__fir_sapling_a__y90_p0', side),
        ('fir_sapling__fir_sapling_b__y0_p0', side), ('fir_sapling__fir_sapling_b__y90_p0', side),
        ('fir_sapling__fir_sapling_c__y0_p0', side), ('fir_sapling__fir_sapling_c__y90_p0', side),
        ('pine_sapling_small__pine_sapling_small_a__y0_p0', side), ('pine_sapling_small__pine_sapling_small_a__y90_p0', side),
        ('pine_sapling_small__pine_sapling_small_b__y0_p0', side), ('pine_sapling_small__pine_sapling_small_c__y0_p0', side),
    ]
    cols, rows, px = 4, 4, 1024
    alb = Image.new('RGBA', (cols * px, rows * px), (0, 0, 0, 0))
    nor = Image.new('RGBA', (cols * px, rows * px), (128, 128, 255, 255))
    sizes = []
    for i, (n, inf) in enumerate(names):
        a = load_cell(b + n + '_albedo.png', px)
        nm = load_cell(b + n + '_normal.png', px)
        pos = ((i % cols) * px, (i // cols) * px)
        alb.paste(a, pos)
        bg = flat_normal((px, px))
        bg.paste(nm, (0, 0), a)
        nor.paste(bg.convert('RGBA'), pos)
        sizes.append(round(inf[n]['width_m'], 3))
    os.makedirs(OUT + '/trees', exist_ok=True)
    dilate(alb).save(OUT + '/trees/conifer_atlas.png')
    nor.convert('RGB').save(OUT + '/trees/conifer_atlas_normal.png')
    return {'cols': cols, 'rows': rows, 'sizes': sizes}


# ------------------------------------------------------------------ leaf clusters
def leaf_sprites(asset):
    d = S + f'/acg/{asset}/{asset}_2K-JPG_'
    col = Image.open(d + 'Color.jpg').convert('RGB')
    op = np.asarray(Image.open(d + 'Opacity.jpg').convert('L'))
    mask = op > 128
    # connected components via simple flood fill on a downsampled grid
    from collections import deque
    h, w = mask.shape
    small = mask[::4, ::4]
    lab = np.zeros(small.shape, np.int32)
    cur = 0
    boxes = []
    for y in range(small.shape[0]):
        for x in range(small.shape[1]):
            if small[y, x] and not lab[y, x]:
                cur += 1
                q = deque([(y, x)])
                lab[y, x] = cur
                y0 = y1 = y
                x0 = x1 = x
                n = 0
                while q:
                    cy, cx = q.popleft()
                    n += 1
                    y0, y1, x0, x1 = min(y0, cy), max(y1, cy), min(x0, cx), max(x1, cx)
                    for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                        ny, nx = cy + dy, cx + dx
                        if 0 <= ny < small.shape[0] and 0 <= nx < small.shape[1] and small[ny, nx] and not lab[ny, nx]:
                            lab[ny, nx] = cur
                            q.append((ny, nx))
                if n > 200:
                    boxes.append((x0 * 4, y0 * 4, x1 * 4 + 4, y1 * 4 + 4))
    rgba = col.copy()
    rgba.putalpha(Image.fromarray(op))
    sprites = []
    for bx in boxes:
        sp = rgba.crop(bx)
        # orient so the stem points down: leaves in these sets are upright already
        sprites.append(sp)
    return sprites


def leaf_cluster(sprites, px, rng, tint, leaf_px, count, twig_col=(78, 62, 46)):
    """A spray of leaves on a branching twig, seen from the side: bottom centre is
    the attachment point. Returns (albedo, normal)."""
    alb = Image.new('RGBA', (px, px), (0, 0, 0, 0))
    nor = Image.new('RGBA', (px, px), (128, 128, 255, 0))
    dr = ImageDraw.Draw(alb)
    # twig skeleton
    pts = []
    main = [(px * 0.5, px * 0.98)]
    ang = -math.pi / 2 + rng.uniform(-0.3, 0.3)
    x, y = main[0]
    for s in range(10):
        ang += rng.uniform(-0.18, 0.18)
        x += math.cos(ang) * px * 0.085
        y += math.sin(ang) * px * 0.085
        main.append((x, y))
    branches = [main]
    for k in range(rng.randint(4, 6)):
        i = rng.randint(2, 7)
        bx, by = main[i]
        a = ang + rng.choice([-1, 1]) * rng.uniform(0.5, 1.1) - math.pi * 0
        a = -math.pi / 2 + rng.choice([-1, 1]) * rng.uniform(0.5, 1.2)
        br = [(bx, by)]
        for s in range(rng.randint(3, 5)):
            a += rng.uniform(-0.2, 0.2)
            bx += math.cos(a) * px * 0.07
            by += math.sin(a) * px * 0.07
            br.append((bx, by))
        branches.append(br)
    for bi, br in enumerate(branches):
        for j in range(len(br) - 1):
            wdt = max(1, int((5 if bi == 0 else 3) * (1 - j / len(br)) * px / 512))
            dr.line([br[j], br[j + 1]], fill=twig_col + (255,), width=wdt)
    for br in branches:
        pts += br[1:]
    # leaves, back to front
    leaves = []
    for n in range(count):
        p = rng.choice(pts)
        leaves.append((p[0] + rng.uniform(-px * 0.05, px * 0.05), p[1] + rng.uniform(-px * 0.05, px * 0.05), rng.random()))
    leaves.sort(key=lambda l: l[2])
    for lx, ly, depth in leaves:
        sp = rng.choice(sprites)
        s = leaf_px * rng.uniform(0.7, 1.15) / max(sp.size)
        sp = sp.resize((max(2, int(sp.size[0] * s)), max(2, int(sp.size[1] * s))), Image.LANCZOS)
        rot = rng.uniform(0, 360)
        sp = sp.rotate(rot, expand=True, resample=Image.BICUBIC)
        shade = 0.55 + 0.45 * depth
        arr = np.asarray(sp).astype(np.float32)
        arr[..., :3] *= np.array(tint) * shade
        sp = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), 'RGBA')
        pos = (int(lx - sp.size[0] / 2), int(ly - sp.size[1] / 2))
        alb.alpha_composite(sp, pos)
        # per-leaf tilted normal
        tx, ty = rng.uniform(-0.6, 0.6), rng.uniform(-0.6, 0.6)
        nz = math.sqrt(max(0.05, 1 - tx * tx - ty * ty))
        ncol = (int((tx * 0.5 + 0.5) * 255), int((ty * 0.5 + 0.5) * 255), int((nz * 0.5 + 0.5) * 255), 255)
        tile = Image.new('RGBA', sp.size, ncol)
        tile.putalpha(sp.getchannel('A'))
        nor.alpha_composite(tile, pos)
    return alb, nor


def birch_bark(px):
    rng = np.random.default_rng(3)
    base = np.ones((px, px, 3), np.float32) * np.array([0.86, 0.85, 0.8])
    n = rng.normal(0, 1, (px // 8, px // 8)).astype(np.float32)
    n = np.asarray(Image.fromarray(((n * 0.15 + 0.5) * 255).clip(0, 255).astype(np.uint8)).resize((px, px), Image.BICUBIC)).astype(np.float32) / 255
    base *= (0.85 + 0.3 * n)[..., None]
    img = Image.fromarray((base.clip(0, 1) * 255).astype(np.uint8))
    dr = ImageDraw.Draw(img)
    r = random.Random(5)
    for k in range(260):  # lenticels: thin horizontal dark dashes
        x, y = r.uniform(0, px), r.uniform(0, px)
        L = r.uniform(px * 0.02, px * 0.12)
        c = int(r.uniform(60, 120))
        for dx in (0, -px, px):
            dr.line([(x + dx, y), (x + dx + L, y + r.uniform(-2, 2))], fill=(c, c - 5, c - 8), width=r.randint(1, 2))
    for k in range(40):  # dark fissure patches: ragged, horizontal-ish
        x, y = r.uniform(0, px), r.uniform(0, px)
        w, h = r.uniform(px * 0.02, px * 0.12), r.uniform(px * 0.006, px * 0.025)
        c = int(r.uniform(35, 75))
        poly = []
        for j in range(10):
            a = math.tau * j / 10
            rr = r.uniform(0.5, 1.0)
            poly.append((math.cos(a) * w * rr, math.sin(a) * h * rr))
        for dx in (0, -px, px):
            for dy in (0, -px, px):
                dr.polygon([(x + dx + u, y + dy + v) for u, v in poly], fill=(c, c - 3, c - 6))
    img = img.filter(ImageFilter.GaussianBlur(0.8))
    return img


def broadleaf():
    rng = random.Random(11)
    beech = leaf_sprites('LeafSet024')
    oak = leaf_sprites('LeafSet016')
    birch = leaf_sprites('LeafSet009')
    print('sprites', len(beech), len(oak), len(birch))
    cols, rows, px = 4, 2, 512
    alb = Image.new('RGBA', (cols * px, rows * px), (0, 0, 0, 0))
    nor = Image.new('RGBA', (cols * px, rows * px), (128, 128, 255, 255))
    # 0,1 beech; 2,3 birch (small, light); 4,5 oak; 6,7 dense hazel-like bush clusters
    specs = [(beech, (0.85, 0.95, 0.8), 44, 150), (beech, (0.8, 0.92, 0.75), 40, 170),
             (birch, (0.95, 1.05, 0.75), 30, 190), (birch, (0.92, 1.0, 0.7), 28, 210),
             (oak, (0.7, 0.85, 0.62), 46, 140), (oak, (0.72, 0.86, 0.6), 42, 160),
             (beech, (0.7, 0.85, 0.65), 48, 220), (birch, (0.75, 0.9, 0.62), 40, 240)]
    for i, (sp, tint, lp, cnt) in enumerate(specs):
        a, n = leaf_cluster(sp, px, rng, tint, lp, cnt)
        pos = ((i % cols) * px, (i // cols) * px)
        alb.paste(a, pos)
        bg = flat_normal((px, px))
        bg.alpha_composite(n)
        nor.paste(bg, pos)
    dilate(alb).save(OUT + '/trees/leaf_atlas.png')
    nor.convert('RGB').save(OUT + '/trees/leaf_atlas_normal.png')


def barks():
    """2x1 atlases of tileable barks: conifer (spruce | pine), broadleaf (beech | birch)."""
    px = 1024
    def acg(id):
        return Image.open(S + f'/acg/{id}/{id}_2K-JPG_Color.jpg').convert('RGB').resize((px, px), Image.LANCZOS), \
               Image.open(S + f'/acg/{id}/{id}_2K-JPG_NormalGL.jpg').convert('RGB').resize((px, px), Image.LANCZOS)
    spruce, spruce_n = acg('Bark014')
    pine = Image.open(S + '/ph_tex/pine_bark_diff_2k.jpg').convert('RGB').resize((px, px), Image.LANCZOS)
    pine_n = Image.open(S + '/ph_tex/pine_bark_nor_gl_2k.jpg').convert('RGB').resize((px, px), Image.LANCZOS)
    beech, beech_n = acg('Bark005')
    beech = np.asarray(beech).astype(np.float32); beech = Image.fromarray((beech * 0.35 + beech.mean(-1, keepdims=True) * 0.65 + np.array([22, 22, 22])).clip(0, 255).astype(np.uint8))
    birch = birch_bark(px)
    for name, (l, r, ln, rn) in {'bark_conifer': (spruce, pine, spruce_n, pine_n), 'bark_broadleaf': (beech, birch, beech_n, Image.new('RGB', (px, px), (128, 128, 255)))}.items():
        a = Image.new('RGB', (px * 2, px)); a.paste(l, (0, 0)); a.paste(r, (px, 0)); a.save(OUT + f'/trees/{name}.jpg', quality=90)
        n = Image.new('RGB', (px * 2, px)); n.paste(ln, (0, 0)); n.paste(rn, (px, 0)); n.save(OUT + f'/trees/{name}_normal.jpg', quality=92)


if __name__ == '__main__':
    what = sys.argv[1:] or ['grass', 'conifer', 'broadleaf', 'barks']
    meta = {}
    if 'grass' in what:
        meta['grass'] = grass()
    if 'conifer' in what:
        meta['conifer'] = conifer()
    if 'broadleaf' in what:
        broadleaf()
    if 'barks' in what:
        barks()
    print(json.dumps(meta))
