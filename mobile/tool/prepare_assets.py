#!/usr/bin/env python3
"""Turns the generated artwork into app images: true-alpha cut-outs, sized WebP, app icons.

  python -m venv v && v/bin/pip install pillow numpy scipy
  v/bin/python -I mobile/tool/prepare_assets.py ~/Downloads/KundliMilan_HD_Art

Source files (ChatGPT, text-free): km_splash_bg, km_home_hero, km_night, km_mandala, km_avatars (3x2),
km_illustrations (3x2), km_states (3x2). Wordmarks and buttons are live text and widgets, never artwork.
"""
import sys
from pathlib import Path
import numpy as np
from PIL import Image, ImageFilter
from scipy import ndimage as ndi

SRC = Path(sys.argv[1]).expanduser()
ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / 'assets/images'
OUT.mkdir(parents=True, exist_ok=True)


def webp(img, name, quality=86):
    img.save(OUT / f'{name}.webp', 'WEBP', quality=quality, method=6, alpha_quality=95)


def fit(img, longest):
    scale = longest / max(img.size)
    if scale >= 1:
        return img
    return img.resize((round(img.width * scale), round(img.height * scale)), Image.LANCZOS)


def alpha_cut(img, thr=236):
    """White connected to the canvas edge becomes transparent; edge pixels lose their white fringe."""
    rgb = np.asarray(img.convert('RGB'), dtype=np.float32)
    white = rgb.min(axis=2) >= thr
    labels, _ = ndi.label(white)
    edge = np.unique(np.concatenate([labels[0], labels[-1], labels[:, 0], labels[:, -1]]))
    bg = np.isin(labels, edge[edge > 0])
    bg = ndi.binary_dilation(bg, iterations=1)
    alpha = 1 - ndi.gaussian_filter(bg.astype(np.float32), 0.8)
    alpha = np.clip((alpha - 0.15) / 0.7, 0, 1)
    a = alpha[..., None]
    colour = np.where(a > 0.02, (rgb - (1 - a) * 255) / np.maximum(a, 0.02), rgb)
    out = np.dstack([np.clip(colour, 0, 255), alpha * 255]).astype(np.uint8)
    return Image.fromarray(out, 'RGBA'), bg


def split_sheet(img, names, longest):
    """Assigns each foreground blob to the grid cell holding its centre, then crops each cell's union."""
    cut, bg = alpha_cut(img)
    arr = np.asarray(cut)
    labels, count = ndi.label(~bg, structure=np.ones((3, 3)))
    h, w = bg.shape
    boxes = ndi.find_objects(labels)
    cells = {}
    for i, box in enumerate(boxes, 1):
        size = (labels[box] == i).sum()
        if size < 12:
            continue
        cy, cx = (box[0].start + box[0].stop) / 2, (box[1].start + box[1].stop) / 2
        cells.setdefault((int(cy * 2 / h), int(cx * 3 / w)), []).append(i)
    for (r, c), name in zip([(r, c) for r in range(2) for c in range(3)], names):
        ids = cells.get((r, c), [])
        mask = np.isin(labels, ids)
        ys, xs = np.where(mask)
        piece = arr.copy()
        piece[..., 3] = np.where(mask, piece[..., 3], 0)
        box = (max(xs.min() - 4, 0), max(ys.min() - 4, 0), xs.max() + 5, ys.max() + 5)
        print(f'  {name}: {len(ids)} blobs, {box[2] - box[0]}x{box[3] - box[1]}')
        webp(fit(Image.fromarray(piece, 'RGBA').crop(box), longest), name, 88)


# Full-bleed scenes.
webp(Image.open(SRC / 'km_splash_bg.png').convert('RGB'), 'splash_bg', 84)
webp(Image.open(SRC / 'km_home_hero.png').convert('RGB'), 'home_hero', 84)
webp(Image.open(SRC / 'km_night.png').convert('RGB'), 'night', 80)

# Cut-outs.
mandala, _ = alpha_cut(Image.open(SRC / 'km_mandala.png'))
webp(fit(mandala, 900), 'mandala', 90)
split_sheet(
    Image.open(SRC / 'km_illustrations.png'),
    ['lotus', 'zodiac_wheel', 'sun_moon', 'kundli_scroll', 'vedic_still_life', 'sprig'],
    720,
)
split_sheet(
    Image.open(SRC / 'km_states.png'),
    ['state_no_people', 'state_no_reports', 'state_no_data', 'state_processing', 'state_report_ready', 'state_success'],
    640,
)

# Portraits: a tighter square around each centred face, for circular avatars.
sheet = Image.open(SRC / 'km_avatars.png').convert('RGB')
cell = sheet.width // 3
order = ['female_1', 'female_2', 'female_3', 'male_1', 'male_2', 'male_3']
for i, name in enumerate(order):
    x, y = (i % 3) * cell, (i // 3) * cell
    size = int(cell * 0.80)
    left = x + (cell - size) // 2
    top = y + int(cell * 0.03)
    webp(sheet.crop((left, top, left + size, top + size)).resize((360, 360), Image.LANCZOS), f'avatar_{name}', 86)

# App icon: the mandala on a deep green field.
S = 1024
yy, xx = np.mgrid[0:S, 0:S].astype(np.float32)
d = np.hypot(xx - S / 2, yy - S * 0.46) / (S * 0.72)
d = np.clip(d, 0, 1)[..., None]
field = (1 - d) * np.array([47, 104, 70]) + d * np.array([14, 44, 29])


def icon(scale):
    base = Image.fromarray(field.astype(np.uint8), 'RGB').convert('RGBA')
    m = mandala.resize((int(S * scale), int(S * scale)), Image.LANCZOS)
    pos = ((S - m.width) // 2, (S - m.height) // 2)
    shadow = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    shadow.paste((0, 0, 0, 150), (pos[0], pos[1] + 14), m.getchannel('A'))
    shadow = shadow.filter(ImageFilter.GaussianBlur(18))
    base = Image.alpha_composite(base, shadow)
    base.alpha_composite(m, pos)
    return base.convert('RGB')


full, safe = icon(0.86), icon(0.66)
for folder, px in [('mdpi', 48), ('hdpi', 72), ('xhdpi', 96), ('xxhdpi', 144), ('xxxhdpi', 192)]:
    full.resize((px, px), Image.LANCZOS).save(ROOT / f'android/app/src/main/res/mipmap-{folder}/ic_launcher.png')
for name, px, art in [
    ('icons/Icon-192', 192, full), ('icons/Icon-512', 512, full),
    ('icons/Icon-maskable-192', 192, safe), ('icons/Icon-maskable-512', 512, safe),
    ('icons/apple-touch-icon', 180, full), ('favicon', 48, full),
]:
    art.resize((px, px), Image.LANCZOS).save(ROOT / f'web/{name}.png')
ios = ROOT / 'ios/Runner/Assets.xcassets/AppIcon.appiconset'
for f in ios.glob('Icon-App-*.png'):
    size, factor = f.stem.split('-')[-1].split('@')
    px = round(float(size.split('x')[0]) * int(factor[0]))
    full.resize((px, px), Image.LANCZOS).save(f)

total = sum(p.stat().st_size for p in OUT.glob('*.webp'))
print(f'{len(list(OUT.glob("*.webp")))} images, {total / 1e6:.2f} MB')
