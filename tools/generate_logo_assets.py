"""
QuickSay Logo Asset Generator v3 — Ultra Professional
=======================================================
Uses Potrace (gold-standard vectorizer) for mathematically perfect Bezier curves.

Pipeline:
1. HSV + color-distance soft matte extraction (removes checkerboard)
2. 16x super-sample with triple-pass Gaussian smoothing
3. Potrace tracing -> optimal cubic Bezier SVG paths
4. High-res anti-aliased PNG rendering from the smooth mask
5. Multi-size PNG export + Windows ICO generation
"""

import cv2
import numpy as np
import potrace
from PIL import Image
import os
import sys
import re

# === CONFIG ===
INPUT_PATH = r"C:\Users\abeek\Downloads\quicksay_cat.png.png"
OUTPUT_DIR = r"C:\QuickSay\Development\gui\assets"
BRAND_COLOR_BGR = (53, 107, 255)   # #FF6B35 in BGR
BRAND_COLOR_RGB = (255, 107, 53)   # #FF6B35 in RGB
BRAND_COLOR_HEX = "#FF6B35"
PNG_SIZES = [16, 32, 48, 64, 128, 256, 512, 1024]
ICO_SIZES = [16, 32, 48, 256]
SUPERSAMPLE_SCALE = 16


def step1_extract_soft_matte(img):
    """Extract orange logo with soft alpha matte using dual-method color analysis."""
    print("[Step 1] Extracting soft alpha matte...")

    h, w = img.shape[:2]
    img_f = img.astype(np.float32)

    # Method A: Euclidean color distance from brand orange
    brand = np.array(BRAND_COLOR_BGR, dtype=np.float32)
    dist = np.sqrt(np.sum((img_f - brand) ** 2, axis=2))
    inner_threshold = 40
    outer_threshold = 100
    alpha_dist = np.clip((outer_threshold - dist) / (outer_threshold - inner_threshold), 0, 1)

    # Method B: HSV-based scoring
    hsv = cv2.cvtColor(img, cv2.COLOR_BGR2HSV)
    hue = hsv[:, :, 0].astype(np.float32)
    sat = hsv[:, :, 1].astype(np.float32)
    val = hsv[:, :, 2].astype(np.float32)

    hue_score = np.where((hue >= 2) & (hue <= 20), 1.0, 0.0)
    hue_score = np.where((hue >= 0) & (hue < 2), hue / 2.0, hue_score)
    hue_score = np.where((hue > 20) & (hue <= 25), (25 - hue) / 5.0, hue_score)
    sat_score = np.clip((sat - 30) / 150.0, 0, 1)
    val_score = np.clip((val - 100) / 100.0, 0, 1)
    alpha_hsv = hue_score * sat_score * val_score

    # Combine: geometric mean for robust extraction
    alpha = np.sqrt(alpha_dist * alpha_hsv)
    alpha = np.clip(alpha, 0, 1)
    alpha_u8 = (alpha * 255).astype(np.uint8)

    # Morphological cleanup
    kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (3, 3))
    alpha_u8 = cv2.morphologyEx(alpha_u8, cv2.MORPH_CLOSE, kernel)

    # Thicken lines for better visibility at small icon sizes
    # Without this, the thin waveform strokes become sub-pixel at 32px and below
    dilate_kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (5, 5))
    alpha_u8 = cv2.dilate(alpha_u8, dilate_kernel, iterations=2)
    print("  Lines thickened (5x5 ellipse, 2 iterations)")

    nonzero = np.count_nonzero(alpha_u8 > 10)
    print(f"  Matte coverage: {nonzero:,} / {h*w:,} ({100*nonzero/(h*w):.1f}%)")
    return alpha_u8


def step1b_crop_to_content(alpha_u8, padding_pct=0.02):
    """
    Crop to the content bounding box and pad to a square canvas.
    Eliminates dead whitespace so the logo fills the entire icon at every size.
    """
    print("[Step 1b] Cropping to content bounding box...")

    coords = cv2.findNonZero(alpha_u8)
    if coords is None:
        print("  WARNING: No content found, returning original")
        return alpha_u8

    x, y, w, h = cv2.boundingRect(coords)
    print(f"  Content bounds: {w}x{h} at ({x},{y})")

    # Crop to content
    cropped = alpha_u8[y:y+h, x:x+w]

    # Pad to square with equal margins on all sides
    max_dim = max(w, h)
    pad = int(max_dim * padding_pct)
    canvas_size = max_dim + 2 * pad

    result = np.zeros((canvas_size, canvas_size), dtype=np.uint8)
    x_off = (canvas_size - w) // 2
    y_off = (canvas_size - h) // 2
    result[y_off:y_off+h, x_off:x_off+w] = cropped

    print(f"  Cropped canvas: {canvas_size}x{canvas_size} (content fills {100*max_dim/canvas_size:.0f}%)")
    return result


def step2_supersample_smooth(alpha_u8):
    """16x super-sample with multi-pass Gaussian smoothing for ultra-smooth edges."""
    print(f"[Step 2] Super-sampling {SUPERSAMPLE_SCALE}x with multi-pass smoothing...")

    h, w = alpha_u8.shape
    tw, th = w * SUPERSAMPLE_SCALE, h * SUPERSAMPLE_SCALE
    print(f"  Upscaling to {tw}x{th}...")

    alpha_large = cv2.resize(alpha_u8, (tw, th), interpolation=cv2.INTER_CUBIC)

    # Pass 1: Heavy blur to melt staircase edges
    k1 = SUPERSAMPLE_SCALE * 4 + 1  # 65
    print(f"  Gaussian pass 1 (kernel {k1})...")
    alpha_large = cv2.GaussianBlur(alpha_large, (k1, k1), 0)
    _, alpha_large = cv2.threshold(alpha_large, 127, 255, cv2.THRESH_BINARY)

    # Pass 2: Medium blur for further refinement
    k2 = SUPERSAMPLE_SCALE * 2 + 1  # 33
    print(f"  Gaussian pass 2 (kernel {k2})...")
    alpha_large = cv2.GaussianBlur(alpha_large, (k2, k2), 0)
    _, alpha_large = cv2.threshold(alpha_large, 127, 255, cv2.THRESH_BINARY)

    # Pass 3: Light blur for final polish
    k3 = SUPERSAMPLE_SCALE + 1  # 17
    if k3 % 2 == 0: k3 += 1
    print(f"  Gaussian pass 3 (kernel {k3})...")
    alpha_large = cv2.GaussianBlur(alpha_large, (k3, k3), 0)
    _, alpha_large = cv2.threshold(alpha_large, 127, 255, cv2.THRESH_BINARY)

    print(f"  Smoothed mask: {tw}x{th}")
    return alpha_large, w, h


def step3_vectorize_potrace(mask_large, orig_w, orig_h):
    """
    Vectorize using Potrace — the gold-standard bitmap tracer.
    Produces mathematically optimal cubic Bezier curves.
    """
    print("[Step 3] Vectorizing with Potrace (optimal Bezier curves)...")

    h, w = mask_large.shape

    # Potrace convention: True = BLACK = foreground to trace
    # Our mask has 255=logo, 0=background, so we need to INVERT
    # because Potrace treats True as the area to fill
    bitmap_data = (mask_large < 127).astype(np.bool_)
    bmp = potrace.Bitmap(bitmap_data)

    # Trace with maximum smoothing settings
    path = bmp.trace(
        turdsize=15,         # Filter speckles smaller than this (in supersampled pixels)
        alphamax=1.334,      # Maximum corner smoothing (1.334 = smoothest possible)
        opticurve=True,      # Enable curve optimization
        opttolerance=0.2     # Low tolerance = more precise curve fitting
    )

    # Build SVG from Potrace output
    scale = 1.0 / SUPERSAMPLE_SCALE
    svg_paths = []
    total_segments = 0

    for curve in path:
        # Start point (potrace Point objects use .x/.y attributes)
        sp = curve.start_point
        d = f"M {sp.x*scale:.3f},{sp.y*scale:.3f} "

        for segment in curve.segments:
            total_segments += 1
            if segment.is_corner:
                # Corner segment: two line segments
                c = segment.c
                ep = segment.end_point
                d += f"L {c.x*scale:.3f},{c.y*scale:.3f} L {ep.x*scale:.3f},{ep.y*scale:.3f} "
            else:
                # Bezier curve segment: cubic bezier (the smooth magic)
                c1 = segment.c1
                c2 = segment.c2
                ep = segment.end_point
                d += f"C {c1.x*scale:.3f},{c1.y*scale:.3f} {c2.x*scale:.3f},{c2.y*scale:.3f} {ep.x*scale:.3f},{ep.y*scale:.3f} "

        d += "Z"
        svg_paths.append(d)

    # Combine all paths into a single <path> with evenodd fill rule
    # This correctly handles holes (like the eyes)
    combined_d = " ".join(svg_paths)

    svg_output = f'''<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {orig_w} {orig_h}" width="{orig_w}" height="{orig_h}">
  <path d="{combined_d}" fill="{BRAND_COLOR_HEX}" fill-rule="evenodd"/>
</svg>'''

    svg_path = os.path.join(OUTPUT_DIR, "logo.svg")
    with open(svg_path, 'w', encoding='utf-8') as f:
        f.write(svg_output)

    size_kb = os.path.getsize(svg_path) / 1024
    curve_count = len(list(path))
    print(f"  Curves: {curve_count}, Segments: {total_segments}")
    print(f"  SVG saved: {svg_path} ({size_kb:.1f} KB)")
    return svg_output


def step4_generate_pngs(mask_large):
    """
    Generate anti-aliased PNGs from the ultra-smooth super-sampled mask.
    The key: LANCZOS downsampling from 16K naturally creates perfect anti-aliased edges.
    """
    print("[Step 4] Generating anti-aliased PNG variants...")

    h, w = mask_large.shape

    # For PNG output, we want SOFT anti-aliased edges, not the hard binary mask.
    # Strategy: Gaussian blur the binary mask BEFORE downsampling to create
    # a soft alpha gradient at the edges, then downsample with LANCZOS.
    # This simulates how professional renderers produce anti-aliased output.

    # Apply a final soft blur WITHOUT re-thresholding (keep the gradient!)
    soft_kernel = SUPERSAMPLE_SCALE * 2 + 1  # 33
    alpha_soft = cv2.GaussianBlur(mask_large, (soft_kernel, soft_kernel), 0)
    # Don't threshold! Keep the 0-255 gradient for anti-aliasing

    # Build RGBA master
    master = np.zeros((h, w, 4), dtype=np.uint8)
    master[:, :, 0] = BRAND_COLOR_RGB[0]  # R
    master[:, :, 1] = BRAND_COLOR_RGB[1]  # G
    master[:, :, 2] = BRAND_COLOR_RGB[2]  # B
    master[:, :, 3] = alpha_soft           # Soft alpha for anti-aliasing

    pil_master = Image.fromarray(master, 'RGBA')

    generated = []
    for size in PNG_SIZES:
        resized = pil_master.resize((size, size), Image.LANCZOS)
        filename = f"logo_{size}.png"
        filepath = os.path.join(OUTPUT_DIR, filename)
        resized.save(filepath, "PNG", optimize=True)
        file_kb = os.path.getsize(filepath) / 1024
        print(f"  {filename}: {size}x{size} ({file_kb:.1f} KB)")
        generated.append((size, filepath))

    return generated


def step5_generate_ico(generated_pngs):
    """Create Windows ICO with multiple embedded resolutions."""
    print("[Step 5] Generating Windows ICO...")

    source_img = None
    for gen_size, filepath in generated_pngs:
        if gen_size == 256:
            source_img = Image.open(filepath)
            break

    if source_img is None:
        print("  ERROR: No 256px PNG found!")
        return

    ico_path = os.path.join(OUTPUT_DIR, "icon.ico")
    source_img.save(ico_path, format='ICO', sizes=[(s, s) for s in ICO_SIZES])

    file_kb = os.path.getsize(ico_path) / 1024
    print(f"  icon.ico: {len(ICO_SIZES)} sizes ({file_kb:.1f} KB)")


def main():
    print("=" * 60)
    print("QuickSay Logo Asset Generator v3")
    print("Potrace + Ultra Smooth Pipeline")
    print("=" * 60)

    if not os.path.exists(INPUT_PATH):
        print(f"ERROR: Input file not found: {INPUT_PATH}")
        sys.exit(1)

    os.makedirs(OUTPUT_DIR, exist_ok=True)

    img = cv2.imread(INPUT_PATH)
    if img is None:
        print(f"ERROR: Could not load image: {INPUT_PATH}")
        sys.exit(1)

    h, w = img.shape[:2]
    print(f"Source: {INPUT_PATH}")
    print(f"Dimensions: {w}x{h}")
    print()

    alpha = step1_extract_soft_matte(img)
    alpha = step1b_crop_to_content(alpha)
    mask_large, orig_w, orig_h = step2_supersample_smooth(alpha)
    step3_vectorize_potrace(mask_large, orig_w, orig_h)
    generated_pngs = step4_generate_pngs(mask_large)
    step5_generate_ico(generated_pngs)

    print()
    print("=" * 60)
    print("DONE! All assets in:")
    print(f"  {OUTPUT_DIR}")
    print()

    for f in sorted(os.listdir(OUTPUT_DIR)):
        fp = os.path.join(OUTPUT_DIR, f)
        size_kb = os.path.getsize(fp) / 1024
        print(f"  {f:20s} {size_kb:8.1f} KB")

    print("=" * 60)


if __name__ == "__main__":
    main()
