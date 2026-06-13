#!/usr/bin/env python3
"""Extract tileable PBR texture triplets from the operator reference photos.

AI-picked crop regions (no human picking): each entry below was chosen by
reading the photo and selecting the largest evenly-lit, occluder-free patch of
the PURE target material, guided by the photo's filename. Only picks with
confidence >= 0.95 are extracted; everything below the bar is recorded in the
SKIPPED table so the manifest stays honest about what was NOT extractable.

Pipeline per crop:
  1. perspective-correct the source quad to an optically-flat rectangle
     (PIL Image.transform QUAD)
  2. cross-fade the right edge into the left and the bottom into the top so
     the tile wraps seamlessly in both axes
  3. resize to OUT_SIZE
  4. derive a normal map (Sobel gradients of blurred luminance)
  5. derive a roughness map (inverse-luminance variation around the
     palette-calibrated base roughness)
  6. write <name>_albedo.png / <name>_normal.png / <name>_rough.png under
     assets/textures/<category>/

Outputs stay in gitignored assets/ — MaterialPalette falls back to its
calibrated flat colors when the PNGs are absent, so the public repo still runs.

Usage:  python tools/extract_texture_atlas.py
"""

from __future__ import annotations

import os
from dataclasses import dataclass

import numpy as np
from PIL import Image, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PHOTOS = os.path.join(ROOT, "assets", "reference_photos")
OUT_ROOT = os.path.join(ROOT, "assets", "textures")
OUT_SIZE = 512
BLEND_FRAC = 0.18  # edge cross-fade width as a fraction of the tile


@dataclass
class Crop:
    name: str            # palette key — files become <name>_albedo.png etc.
    category: str        # output subfolder under assets/textures/
    photo: str           # path relative to assets/reference_photos/
    # Source quad in FRACTIONAL image coords, order TL, TR, BR, BL.
    # Non-rectangular quads encode the perspective correction.
    quad: tuple
    confidence: float    # AI pick confidence that the quad is pure material
    base_roughness: float  # palette-calibrated roughness the rough map varies around
    rough_spread: float  # +/- variation injected from luminance detail
    normal_strength: float
    note: str
    # How strongly to remove the photo's low-frequency lighting gradient before
    # tiling (0 = keep, 1 = fully flat). Smooth surfaces need ~0.85 or the edge
    # cross-fade shows as a band; busy/stained surfaces keep more so their
    # character survives.
    flatten: float = 0.6


CROPS = [
    Crop("concrete_worn", "floor", "building/hal_0_storage_racks_wood_supports_texture.png",
         ((0.60, 0.80), (0.85, 0.79), (0.87, 0.955), (0.56, 0.965)),
         0.97, 0.88, 0.08, 2.2,
         "Dry foreground floor patch right of the wet streak, left of the photo watermark; "
         "receding quad de-skews the camera pitch."),
    Crop("dirt_buildup", "floor", "machines/_extruder_silo.png",
         ((0.34, 0.85), (0.82, 0.85), (0.86, 0.96), (0.28, 0.965)),
         0.96, 0.97, 0.03, 2.0,
         "Brown caked-dirt floor in front of the silo, below the LDPE lumps."),
    Crop("timber_dark", "building", "building/_wooden_V_shape_support_beams.png",
         ((0.53, 0.31), (0.66, 0.31), (0.66, 0.53), (0.53, 0.53)),
         0.96, 0.92, 0.06, 2.5,
         "Frontal face of the V-beam trunk, right of the conduit pipe, "
         "between the red sign and the floor clutter."),
    Crop("stainless_weathered", "machines", "machines/voorwas_trommel_2.png",
         ((0.10, 0.21), (0.48, 0.185), (0.48, 0.245), (0.10, 0.27)),
         0.96, 0.65, 0.20, 1.6,
         "Drum shell upper-left, ABOVE the cage fence top rail and above the TANK A "
         "stencil — the only unobstructed weathered-stainless patch across the three "
         "tank photos. Sheared quad follows the drum-axis tilt."),
    Crop("grating_steel", "building", "machines/voorwas_trommel_1.png",
         ((0.62, 0.78), (0.84, 0.78), (0.86, 0.91), (0.60, 0.91)),
         0.95, 0.55, 0.15, 3.0,
         "Catwalk grating right of the dropped glove, clear of the angled edge beam; "
         "receding quad flattens the walk angle."),
    Crop("paint_cream_steel", "machines", "machines/_extruder_silo.png",
         ((0.49, 0.378), (0.55, 0.378), (0.55, 0.405), (0.49, 0.405)),
         0.96, 0.55, 0.06, 1.2,
         "Clean cream panel of the silo upper box, between the two slot windows.",
         0.85),
    Crop("ppe_hivis_orange", "ppe", "people/worker_outfit.png",
         ((0.756, 0.462), (0.768, 0.462), (0.768, 0.488), (0.756, 0.488)),
         0.95, 0.80, 0.06, 1.5,
         "Plain orange fabric on the worker's back, below the horizontal reflective band, "
         "inside the torso silhouette.",
         0.85),
    Crop("ppe_denim_pants", "ppe", "people/worker_outfit.png",
         ((0.655, 0.59), (0.73, 0.59), (0.73, 0.70), (0.655, 0.70)),
         0.95, 0.85, 0.05, 1.5,
         "Blue work jeans, thigh area, inside the leg silhouette and clear of the hose loop.",
         0.85),
]

# Targets the filenames promise but where NO region cleared the 0.95 bar.
# (target, photo, confidence, why)
SKIPPED = [
    ("nir_sorter_orange_enamel", "machines/titech_tomra_1.jpg", 0.20,
     "Photo is an interior drum shot (wrapped material on the rotor) — the orange shell is not in frame."),
    ("paint_navy_industrial", "machines/_trilzeef.png", 0.70,
     "Side panels are shadowed and oblique; no evenly-lit flat navy region."),
    ("paint_safety_yellow_fresh", "building/yellow_ladders_railings_lines.png", 0.80,
     "Only thin railing tubes / toe boards — no flat patch big enough for a clean tile."),
    ("ppe_reflective_stripe", "people/worker_outfit.png", 0.60,
     "Stripes are a few px wide and specular — would alias into noise."),
    ("concrete_wet", "machines/flotatietank_3A.png + building/yellow_ladders_railings_lines.png", 0.80,
     "Every wet floor patch is crossed by drains, yellow walkway lines, or scraps — "
     "three quads tried; the calibrated low-roughness flat material stays."),
    ("paint_yellow_peeling", "machines/voorwas_trommel_1.png", 0.75,
     "Frame post is too narrow and motion-blurred — two sheared-quad attempts still "
     "mixed in background and out-of-focus grating; flat palette color stays."),
    ("timber_post_washline", "people/worker_outfit.png", 0.55,
     "Wash-line wooden posts are partially occluded by the worker and the hose."),
]


def _to_px(quad, size):
    w, h = size
    return [(fx * w, fy * h) for fx, fy in quad]


def extract_flat(img: Image.Image, quad) -> Image.Image:
    """Perspective-correct the fractional quad to a flat rectangle."""
    tl, tr, br, bl = _to_px(quad, img.size)
    # Output size from average source edge lengths so detail density is kept.
    ow = int((np.hypot(tr[0] - tl[0], tr[1] - tl[1]) +
              np.hypot(br[0] - bl[0], br[1] - bl[1])) / 2)
    oh = int((np.hypot(bl[0] - tl[0], bl[1] - tl[1]) +
              np.hypot(br[0] - tr[0], br[1] - tr[1])) / 2)
    ow, oh = max(ow, 64), max(oh, 64)
    # PIL QUAD data order: TL, BL, BR, TR.
    data = (*tl, *bl, *br, *tr)
    return img.transform((ow, oh), Image.QUAD, data=data,
                         resample=Image.BICUBIC)


def flatten_illumination(a: np.ndarray, strength: float) -> np.ndarray:
    """Remove the low-frequency lighting gradient baked into the photo.

    Subtracts a heavy Gaussian blur (the illumination field) and re-adds the
    mean color, so the texture is photometrically flat and the seamless
    cross-fade no longer reveals brightness bands.
    """
    if strength <= 0.0:
        return a
    img = Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))
    sigma = min(a.shape[0], a.shape[1]) / 6.0
    blur = np.asarray(img.filter(ImageFilter.GaussianBlur(sigma)), dtype=np.float32)
    mean = a.reshape(-1, a.shape[-1]).mean(axis=0)
    return a + (mean - blur) * strength


def make_seamless(a: np.ndarray, frac: float = BLEND_FRAC) -> np.ndarray:
    """Cross-fade right edge into left and bottom into top so the tile wraps."""
    h, w = a.shape[:2]
    bw, bh = max(int(w * frac), 4), max(int(h * frac), 4)
    out = a[:, : w - bw].astype(np.float32).copy()
    ramp = np.linspace(0.0, 1.0, bw, dtype=np.float32)[None, :, None]
    out[:, :bw] = a[:, w - bw:] * (1.0 - ramp) + a[:, :bw] * ramp
    a = out
    h, w = a.shape[:2]
    out = a[: h - bh].copy()
    ramp = np.linspace(0.0, 1.0, bh, dtype=np.float32)[:, None, None]
    out[:bh] = a[h - bh:] * (1.0 - ramp) + a[:bh] * ramp
    return np.clip(out, 0, 255).astype(np.uint8)


def derive_normal(albedo: Image.Image, strength: float) -> Image.Image:
    gray = np.asarray(
        albedo.convert("L").filter(ImageFilter.GaussianBlur(1.2)),
        dtype=np.float32) / 255.0
    # Wrap-aware gradients so the normal map tiles like the albedo does.
    dx = (np.roll(gray, -1, axis=1) - np.roll(gray, 1, axis=1)) * strength
    dy = (np.roll(gray, -1, axis=0) - np.roll(gray, 1, axis=0)) * strength
    nz = np.ones_like(gray)
    length = np.sqrt(dx * dx + dy * dy + nz * nz)
    n = np.stack([-dx / length, dy / length, nz / length], axis=-1)
    return Image.fromarray(((n * 0.5 + 0.5) * 255).astype(np.uint8), "RGB")


def derive_roughness(albedo: Image.Image, base: float, spread: float) -> Image.Image:
    gray = np.asarray(albedo.convert("L"), dtype=np.float32) / 255.0
    centered = gray - float(gray.mean())
    # Brighter spots read as smoother/worn-shiny; darker pits read rougher.
    rough = np.clip(base - centered * spread * 4.0, 0.02, 1.0)
    return Image.fromarray((rough * 255).astype(np.uint8), "L")


def main() -> None:
    manifest = ["# Texture extraction manifest — generated by tools/extract_texture_atlas.py",
                "# AI-picked source quads, confidence >= 0.95 required for extraction.", ""]
    for c in CROPS:
        src = os.path.join(PHOTOS, c.photo.replace("/", os.sep))
        img = Image.open(src).convert("RGB")
        flat = extract_flat(img, c.quad)
        arr = flatten_illumination(np.asarray(flat, dtype=np.float32), c.flatten)
        tile = make_seamless(arr)
        albedo = Image.fromarray(tile).resize((OUT_SIZE, OUT_SIZE), Image.LANCZOS)
        normal = derive_normal(albedo, c.normal_strength)
        rough = derive_roughness(albedo, c.base_roughness, c.rough_spread)
        out_dir = os.path.join(OUT_ROOT, c.category)
        os.makedirs(out_dir, exist_ok=True)
        albedo.save(os.path.join(out_dir, f"{c.name}_albedo.png"))
        normal.save(os.path.join(out_dir, f"{c.name}_normal.png"))
        rough.save(os.path.join(out_dir, f"{c.name}_rough.png"))
        manifest.append(
            f"EXTRACTED {c.category}/{c.name}  conf={c.confidence:.2f}  "
            f"src={c.photo}  quad={c.quad}\n  {c.note}")
        print(f"[ok] {c.category}/{c.name}  <- {c.photo}  (conf {c.confidence:.2f})")
    manifest.append("")
    for target, photo, conf, why in SKIPPED:
        manifest.append(f"SKIPPED   {target}  conf={conf:.2f}  src={photo}\n  {why}")
        print(f"[skip] {target}  (conf {conf:.2f} < 0.95)")
    os.makedirs(OUT_ROOT, exist_ok=True)
    with open(os.path.join(OUT_ROOT, "MANIFEST.txt"), "w", encoding="utf-8") as f:
        f.write("\n".join(manifest) + "\n")
    print(f"\n{len(CROPS)} triplets -> {OUT_ROOT}")
    print(f"{len(SKIPPED)} targets below the 0.95 bar (see MANIFEST.txt)")


if __name__ == "__main__":
    main()
