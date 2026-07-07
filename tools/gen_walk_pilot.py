#!/usr/bin/env python
# =============================================================================
# DUSTFALL — WALK-CYCLE SHEET PILOT (DEV-ONLY)
# Tests whether flux.1-dev can produce usable walk-cycle frames by generating
# all frames in ONE image (a horizontal sprite sheet), which keeps the
# character consistent across frames — the thing per-frame text2img can't do.
#
# Pipeline: generate sheet -> gap-based slice into frames -> common-scale,
# bottom-aligned processing (feet stay planted) -> godot/assets/sprites/
# <char>_side_walk{0..N}.png + a QA strip in assets_raw/ for eyeballing.
#
# Usage: python tools/gen_walk_pilot.py [character] [--frames N] [--force]
# =============================================================================
import os
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(__file__))
from gen_assets import CHARACTERS, STYLE_PIXEL, gen, remove_bg, save_raw

ROOT = os.path.join(os.path.dirname(__file__), "..")
SPRITES = os.path.join(ROOT, "godot", "assets", "sprites")
RAW = os.path.join(ROOT, "assets_raw", "walk_pilot")


def sheet_prompt(char_id, frames):
    base = CHARACTERS[char_id]
    # keep the shipped character description; swap the pose phrasing for a sheet
    desc = base.replace("standing idle facing viewer", "").rstrip(", ")
    return (
        f"pixel art sprite sheet, {frames} frames of a walking animation cycle, "
        f"the SAME character repeated {frames} times in a single horizontal row, "
        f"evenly spaced, each frame a different step of the walk, "
        f"full side profile view facing left, {desc}, "
        f"plain solid white background, no text, no grid lines, " + STYLE_PIXEL
    )


def find_frame_spans(img, expected, white_thresh=242, min_gap=8):
    """Split a white-background sheet into content spans by column whiteness."""
    g = img.convert("L")
    w, h = g.size
    px = g.load()
    col_has_content = []
    for x in range(w):
        dark = sum(1 for y in range(0, h, 3) if px[x, y] < white_thresh)
        col_has_content.append(dark > h // 60)
    spans = []
    start = None
    for x, has in enumerate(col_has_content):
        if has and start is None:
            start = x
        elif not has and start is not None:
            spans.append((start, x))
            start = None
    if start is not None:
        spans.append((start, w))
    # merge spans separated by tiny gaps (inside-character white pockets)
    merged = []
    for s in spans:
        if merged and s[0] - merged[-1][1] < min_gap:
            merged[-1] = (merged[-1][0], s[1])
        else:
            merged.append(list(s))
    merged = [tuple(m) for m in merged if m[1] - m[0] > 20]
    if len(merged) != expected:
        print(f"  ! gap-slice found {len(merged)} spans (wanted {expected}) — "
              f"falling back to equal columns")
        step = w // expected
        merged = [(i * step, (i + 1) * step) for i in range(expected)]
    return merged


def process_frames(sheet, spans, target_h=96):
    """Cut frames, remove bg, then scale ALL by one factor and bottom-align
    so the feet baseline and body size stay identical across frames."""
    frames = []
    for (x0, x1) in spans:
        f = sheet.crop((x0, 0, x1, sheet.height))
        f = remove_bg(f)
        bbox = f.getbbox()
        frames.append(f.crop(bbox) if bbox else f)
    max_h = max(f.height for f in frames)
    scale = target_h / max_h
    canvas_w = max(int(f.width * scale) for f in frames) + 4
    out = []
    for f in frames:
        nw, nh = max(8, int(f.width * scale)), max(8, int(f.height * scale))
        f = f.resize((nw, nh), Image.BOX)
        c = Image.new("RGBA", (canvas_w, target_h), (0, 0, 0, 0))
        c.paste(f, ((canvas_w - nw) // 2, target_h - nh))  # bottom-aligned
        out.append(c)
    return out


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    char = args[0] if args else "gunslinger"
    frames_n = 4
    if "--frames" in sys.argv:
        frames_n = int(sys.argv[sys.argv.index("--frames") + 1])
    force = "--force" in sys.argv
    if char not in CHARACTERS:
        sys.exit(f"unknown character: {char}")

    first_out = os.path.join(SPRITES, f"{char}_side_walk0.png")
    if os.path.exists(first_out) and not force:
        sys.exit(f"{first_out} exists — use --force to regenerate")

    prompt = sheet_prompt(char, frames_n)
    print(f"[{char}] generating {frames_n}-frame walk sheet...")
    print("  prompt:", prompt[:120], "...")
    data = gen(prompt, w=1344, h=768, seed=hash(char + "_walk") % 100000)
    raw_path = os.path.join(RAW, f"{char}_sheet.png")
    save_raw(data, raw_path)

    sheet = Image.open(raw_path)
    spans = find_frame_spans(sheet, frames_n)
    print(f"  frame spans: {spans}")
    frames = process_frames(sheet, spans)

    os.makedirs(SPRITES, exist_ok=True)
    for i, f in enumerate(frames):
        p = os.path.join(SPRITES, f"{char}_side_walk{i}.png")
        f.save(p)
        print(f"  saved {p} ({f.width}x{f.height})")

    # QA strip: frames side by side next to the shipped static side sprite
    static_p = os.path.join(SPRITES, f"{char}_side.png")
    cells = frames[:]
    if os.path.exists(static_p):
        cells.insert(0, Image.open(static_p).convert("RGBA"))
    strip_w = sum(c.width + 6 for c in cells)
    strip = Image.new("RGBA", (strip_w, max(c.height for c in cells)), (34, 24, 12, 255))
    x = 0
    for c in cells:
        strip.paste(c, (x, strip.height - c.height), c)
        x += c.width + 6
    qa_path = os.path.join(RAW, f"{char}_qa_strip.png")
    strip.save(qa_path)
    print(f"  QA strip (static + frames): {qa_path}")


if __name__ == "__main__":
    main()
