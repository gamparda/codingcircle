"""Extract transparent game sprites from the supplied role sheets.

The sheets use white or near-white backgrounds.  We only remove background-like
pixels connected to the canvas edge, which keeps enclosed white costume details.
Run from the repository root with: python tools/extract_sprites.py
"""

from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets" / "source" / "role_sheets"
OUTPUT = ROOT / "assets" / "units"

SHEETS = {
    "tanker": SOURCE / "tanker_sheet.jpg",
    "healer": SOURCE / "healer_sheet.png",
    "archer": SOURCE / "archer_sheet.png",
    "swordsman": SOURCE / "swordsman_sheet.png",
}

# Chosen readable gameplay poses: tank idle, healer staff-walk, archer idle,
# swordsman idle. Values are content bounds discovered from the source sheets.
SELECTED_BOUNDS = {
    "tanker": (108, 56, 271, 265),
    "healer": (93, 591, 280, 829),
    "archer": (77, 172, 252, 401),
    "swordsman": (56, 231, 255, 493),
}

# White background pockets completely enclosed by thin equipment outlines.
# Coordinates are relative to the padded extracted crop.
INTERNAL_BACKGROUND_REGIONS = {
    "archer": [(121, 107, 160, 157)],  # inside the bow and bowstring
}


def edge_connected_background(rgb: np.ndarray) -> np.ndarray:
    """Return a mask for near-neutral bright pixels connected to an edge."""
    rgb16 = rgb.astype(np.int16)
    minimum = rgb16.min(axis=2)
    chroma = rgb16.max(axis=2) - minimum
    candidate = (minimum >= 210) & (chroma <= 28)
    labels, _ = ndimage.label(candidate)
    edge_labels = np.unique(
        np.concatenate((labels[0], labels[-1], labels[:, 0], labels[:, -1]))
    )
    edge_labels = edge_labels[edge_labels != 0]
    return np.isin(labels, edge_labels)


def make_rgba(path: Path) -> Image.Image:
    image = Image.open(path).convert("RGB")
    rgb = np.asarray(image)
    background = edge_connected_background(rgb)
    alpha = np.full(rgb.shape[:2], 255, dtype=np.uint8)
    alpha[background] = 0

    # Defringe only directly outside the opaque silhouette.  This removes pale
    # JPEG/resize halos while preserving the hard pixel-art outline.
    fringe = ndimage.binary_dilation(background, iterations=3) & ~background
    edge_color = np.median(
        np.concatenate((rgb[0], rgb[-1], rgb[:, 0], rgb[:, -1])), axis=0
    )
    distance = np.linalg.norm(rgb.astype(np.float32) - edge_color, axis=2)
    fringe_alpha = np.clip((distance - 4.0) * 7.0, 0.0, 255.0).astype(np.uint8)
    alpha[fringe] = np.minimum(alpha[fringe], fringe_alpha[fringe])

    return Image.fromarray(np.dstack((rgb, alpha)), "RGBA")


def components(image: Image.Image) -> list[tuple[int, int, int, int, int]]:
    alpha = np.asarray(image.getchannel("A"))
    labels, count = ndimage.label(alpha > 48)
    objects = ndimage.find_objects(labels)
    found = []
    for label_id in range(1, count + 1):
        region = objects[label_id - 1]
        if region is None:
            continue
        ys, xs = region
        area = int(np.count_nonzero(labels[region] == label_id))
        if area < 350:
            continue
        found.append((xs.start, ys.start, xs.stop, ys.stop, area))
    return sorted(found, key=lambda box: (box[1], box[0]))


def clear_internal_background(
    image: Image.Image, regions: list[tuple[int, int, int, int]]
) -> Image.Image:
    """Clear known enclosed background pockets without touching white clothes."""
    rgba = np.array(image)
    rgb = rgba[:, :, :3].astype(np.int16)
    minimum = rgb.min(axis=2)
    chroma = rgb.max(axis=2) - minimum
    candidate = (minimum >= 210) & (chroma <= 28)
    for left, top, right, bottom in regions:
        window = np.zeros(candidate.shape, dtype=bool)
        window[top:bottom, left:right] = True
        hole = candidate & window
        rgba[hole, 3] = 0
        fringe = ndimage.binary_dilation(hole, iterations=2) & ~hole & window
        distance = np.linalg.norm(rgb.astype(np.float32) - 255.0, axis=2)
        fringe_alpha = np.clip((distance - 3.0) * 8.0, 0.0, 255.0).astype(np.uint8)
        rgba[fringe, 3] = np.minimum(rgba[fringe, 3], fringe_alpha[fringe])
    return Image.fromarray(rgba, "RGBA")


def main() -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    extracted: dict[str, Image.Image] = {}
    for role, path in SHEETS.items():
        rgba = make_rgba(path)
        print(role, rgba.size)
        for index, box in enumerate(components(rgba)):
            print(f"  {index:02d}: {box}")

        left, top, right, bottom = SELECTED_BOUNDS[role]
        padding = 8
        crop = rgba.crop(
            (
                max(0, left - padding),
                max(0, top - padding),
                min(rgba.width, right + padding),
                min(rgba.height, bottom + padding),
            )
        )
        crop = clear_internal_background(
            crop, INTERNAL_BACKGROUND_REGIONS.get(role, [])
        )
        crop.save(OUTPUT / f"{role}.png")
        extracted[role] = crop

    # A dark preview catches pale halos that are invisible on the white sources.
    preview = Image.new("RGBA", (960, 360), (10, 13, 22, 255))
    for index, role in enumerate(SHEETS):
        sprite = extracted[role].copy()
        sprite.thumbnail((190, 280), Image.Resampling.NEAREST)
        x = 35 + index * 235 + (190 - sprite.width) // 2
        y = 25 + (280 - sprite.height)
        preview.alpha_composite(sprite, (x, y))
    preview.save(OUTPUT / "cutout_preview.png")


if __name__ == "__main__":
    main()
