"""Cuts green-screen (#00FF00) unit sheets and black-background effect sheets into game frames.

    python tools/extract_green_units.py            # every unit and effect below
    python tools/extract_green_units.py joker      # one unit

Unit sheets (assets/source/role_sheets/<sheet>_sheet.png) hold one pose group per row. Each row is split at
the empty columns between poses; detached bits (sparks, a thrown card) join the pose nearest to them until
the row has the expected number of poses. Every frame of a unit is drawn on one shared canvas with the feet
centred at the bottom, so frames swap without jumping. Outputs:
    assets/units/<kind>.png                       portrait (first idle pose)
    assets/units/animations/<kind>/<group>_<i>.png
Effect rows become assets/units/effects/<name>_<i>.png with alpha taken from brightness (additive art).
"""
from pathlib import Path
import sys

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'assets/source/role_sheets'
OUT = ROOT / 'assets/units'

# kind: (sheet, [(group, poses) per row, top to bottom]); group None skips a row.
UNITS = {
    'general': ('general', [('idle', 6), ('walk', 6), ('attack', 5), ('skill', 6)]),
    'bomber': ('bomber', [('idle', 8), ('walk', 8), ('attack', 5), ('death', 7)]),
    'joker': ('joker', [('idle', 8), ('walk', 8), ('attack', 5), (None, 7)]),
    'king': ('king', [('idle', 8), ('walk', 8), ('attack', 5), ('skill', 7)]),
    'royal_guard': ('king_guard', [('idle', 8), ('walk', 8), ('attack', 5), ('death', 6)]),
    'hero': ('hero', [('idle', 8), ('walk', 8), ('attack', 5), ('skill', 7)]),
    'raider': ('raider', [('idle', 8), ('walk', 8), ('attack', 5), ('skill', 7)]),
    'preacher': ('preacher', [('idle', 8), ('walk', 8), ('attack', 5), ('skill', 7)]),
    'psychic': ('psychic', [('idle', 8), ('walk', 8), ('attack', 5), ('skill', 7)]),
    'shaman': ('shaman', [('idle', 8), ('walk', 8), ('attack', 5), ('skill', 6)]),
}
# name: (sheet, row index, poses)
EFFECTS = {
    'bomb_blast': ('new_effects_a', 1, 8),
    'joker_blink': ('new_effects_a', 2, 6),
    'royal_summon': ('new_effects_b', 3, 6),
    'psychic_portal': ('new_effects_a', 4, 7),
    'coin_steal': ('new_effects_b', 0, 6),
    'gift_absorb': ('new_effects_b', 1, 6),
    'hero_aura': ('new_effects_b', 2, 6),
    'convert_swirl': ('new_effects_b', 4, 6),
}


def key_green(image: Image.Image) -> np.ndarray:
    """RGBA float array: green screen removed, green spill pulled out of the edges."""
    rgb = np.asarray(image.convert('RGB')).astype(np.float64)
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    greenness = g - np.maximum(r, b)
    alpha = np.clip(1.0 - (greenness - 40.0) / 80.0, 0.0, 1.0)
    g = np.minimum(g, np.maximum(r, b) + 10.0)
    alpha[alpha < 0.06] = 0.0
    return np.dstack([r, g, b, alpha * 255.0])


def key_black(image: Image.Image) -> np.ndarray:
    rgb = np.asarray(image.convert('RGB')).astype(np.float64)
    alpha = rgb.max(axis=2)
    alpha[alpha < 14.0] = 0.0
    safe = np.where(alpha > 0.0, alpha, 1.0)[..., None]
    colour = np.clip(rgb * 255.0 / safe, 0.0, 255.0)
    return np.dstack([colour, alpha])


def bands(mask: np.ndarray, rows: int) -> list:
    """The `rows` horizontal bands holding art; small bands (a coin tossed high) join their neighbour."""
    filled = mask.sum(axis=1) > 2
    found, start = [], None
    for y, on in enumerate(list(filled) + [False]):
        if on and start is None:
            start = y
        elif not on and start is not None:
            found.append([start, y])
            start = None
    while len(found) > rows:
        # Merge the smallest band into the closer neighbour.
        index = min(range(len(found)), key=lambda i: found[i][1] - found[i][0])
        if index == 0:
            other = 1
        elif index == len(found) - 1:
            other = index - 1
        else:
            other = index - 1 if found[index][0] - found[index - 1][1] <= found[index + 1][0] - found[index][1] else index + 1
        lo, hi = sorted((index, other))
        found[lo] = [min(found[lo][0], found[hi][0]), max(found[lo][1], found[hi][1])]
        del found[hi]
    assert len(found) == rows, ('expected %d rows, found %d' % (rows, len(found)))
    return found


def columns(mask: np.ndarray, poses: int) -> list:
    """Splits a band at empty columns, then merges the narrowest pieces into their closest neighbour."""
    filled = mask.sum(axis=0) > 0
    pieces, start = [], None
    for x, on in enumerate(list(filled) + [False]):
        if on and start is None:
            start = x
        elif not on and start is not None:
            pieces.append([start, x])
            start = None
    def weight(p):
        return int(mask[:, p[0]:p[1]].sum())
    while len(pieces) > poses:
        index = min(range(len(pieces)), key=lambda i: weight(pieces[i]))
        if index == 0:
            other = 1
        elif index == len(pieces) - 1:
            other = index - 1
        else:
            other = index - 1 if pieces[index][0] - pieces[index - 1][1] <= pieces[index + 1][0] - pieces[index][1] else index + 1
        lo, hi = sorted((index, other))
        pieces[lo] = [pieces[lo][0], pieces[hi][1]]
        del pieces[hi]
    assert len(pieces) == poses, ('expected %d poses, found %d' % (poses, len(pieces)))
    return pieces


def feet_anchor(alpha: np.ndarray) -> float:
    """x of the feet: the alpha-weighted middle of the lowest rows (weapons and capes do not move it)."""
    ys = np.nonzero(alpha.sum(axis=1) > 0)[0]
    bottom = alpha[max(0, ys.max() - 14):ys.max() + 1]
    weights = bottom.sum(axis=0)
    cumulative = np.cumsum(weights)
    return float(np.searchsorted(cumulative, cumulative[-1] / 2.0))


def body_anchor(alpha: np.ndarray) -> float:
    """x of the torso (middle third of the height) for walk cycles, where legs swing apart."""
    ys = np.nonzero(alpha.sum(axis=1) > 0)[0]
    top, height = ys.min(), ys.max() - ys.min()
    band = alpha[top + int(height * 0.35):top + int(height * 0.65)]
    weights = band.sum(axis=0)
    cumulative = np.cumsum(weights)
    return float(np.searchsorted(cumulative, cumulative[-1] / 2.0))


def cut_unit(kind: str) -> dict:
    sheet_name, rows = UNITS[kind]
    keyed = key_green(Image.open(SOURCE / (sheet_name + '_sheet.png')))
    alpha = keyed[..., 3]
    mask = alpha > 60.0
    frames = {}
    for (y0, y1), (group, poses) in zip(bands(mask, len(rows)), rows):
        if group is None:
            continue
        band_mask = mask[y0:y1]
        frames[group] = []
        for x0, x1 in columns(band_mask, poses):
            crop = keyed[y0:y1, x0:x1].copy()
            # Pixels of the neighbouring pose never reach into this column range (they were split at empty
            # columns), so the crop is this pose alone.
            a = crop[..., 3]
            ys = np.nonzero(a.sum(axis=1) > 0)[0]
            xs = np.nonzero(a.sum(axis=0) > 0)[0]
            crop = crop[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
            anchor = body_anchor(crop[..., 3]) if group == 'walk' else feet_anchor(crop[..., 3])
            frames[group].append((crop, anchor))
    all_frames = [frame for group in frames.values() for frame in group]
    half = int(max(max(anchor, crop.shape[1] - anchor) for crop, anchor in all_frames)) + 8
    height = max(crop.shape[0] for crop, _ in all_frames) + 16
    folder = OUT / 'animations' / kind
    folder.mkdir(parents=True, exist_ok=True)
    for old in folder.glob('*.png'):
        old.unlink()
    for group, images in frames.items():
        if group == 'idle':
            continue
        for index, (crop, anchor) in enumerate(images):
            canvas = np.zeros((height, half * 2, 4))
            left = int(round(half - anchor))
            top = height - 8 - crop.shape[0]
            canvas[top:top + crop.shape[0], left:left + crop.shape[1]] = crop
            Image.fromarray(canvas.round().astype(np.uint8), 'RGBA').save(folder / ('%s_%d.png' % (group, index)))
    idle = frames['idle'][0][0]
    portrait = np.zeros((idle.shape[0] + 16, idle.shape[1] + 16, 4))
    portrait[8:8 + idle.shape[0], 8:8 + idle.shape[1]] = idle
    Image.fromarray(portrait.round().astype(np.uint8), 'RGBA').save(OUT / (kind + '.png'))
    return {group: len(images) for group, images in frames.items() if group != 'idle'}


def cut_effect(name: str) -> int:
    sheet_name, row, poses = EFFECTS[name]
    keyed = key_black(Image.open(SOURCE / (sheet_name + '.png')))
    mask = keyed[..., 3] > 30.0
    y0, y1 = bands(mask, 5)[row]
    pieces = columns(mask[y0:y1], poses)
    # One box for every frame keeps them registered: the effect grows in place instead of jumping.
    width = max(x1 - x0 for x0, x1 in pieces)
    folder = OUT / 'effects'
    folder.mkdir(parents=True, exist_ok=True)
    for index, (x0, x1) in enumerate(pieces):
        centre = (x0 + x1) // 2
        left = max(0, centre - width // 2 - 4)
        crop = keyed[y0:y1, left:left + width + 8]
        Image.fromarray(crop.round().astype(np.uint8), 'RGBA').save(folder / ('%s_%d.png' % (name, index)))
    return poses


def main(argv: list) -> None:
    wanted = argv[1:] or list(UNITS) + list(EFFECTS)
    for name in wanted:
        if name in UNITS:
            print(name, cut_unit(name))
        else:
            print(name, cut_effect(name))


if __name__ == '__main__':
    main(sys.argv)
