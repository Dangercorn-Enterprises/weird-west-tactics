#!/usr/bin/env python
# =============================================================================
# DUSTFALL — SPRITE QA + REPAIR
# Sweeps godot/assets/sprites for broken views and repairs them:
#   blank/thin  -> reprocess the raw with tighter bg-removal tolerance;
#                  if still blank, regenerate (new seed, stronger wording)
# Prints an opaque-ratio report so face-showing "backs" can be eyeballed fast.
# Run after any sprite batch: python tools/qa_sprites.py
# =============================================================================
import os, sys, importlib.util
from PIL import Image

ROOT = os.path.join(os.path.dirname(__file__), "..")
SPRITES = os.path.join(ROOT, "godot", "assets", "sprites")
RAWS = os.path.join(ROOT, "assets_raw", "sprites")

spec = importlib.util.spec_from_file_location("ga", os.path.join(ROOT, "tools", "gen_assets.py"))
ga = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ga)

BACK_STRONG = (", rear view seen from directly behind, showing the back of the head "
               "and the back of the coat, no face visible, no eyes")

def opaque_ratio(path):
    img = Image.open(path).convert("RGBA")
    a = img.getchannel("A")
    data = list(a.get_flattened_data()) if hasattr(a, "get_flattened_data") else list(a.getdata())
    return sum(1 for v in data if v > 32) / max(1, len(data))

def base_and_view(fname):
    stem = fname[:-4]
    for suffix in ["_back", "_side_r", "_side"]:
        if stem.endswith(suffix):
            return stem[: -len(suffix)], suffix[1:]
    return stem, "front"

def _try_result(img, out):
    """save ONLY if the processed sprite is actually usable"""
    if not img.getbbox() or img.height < 60:
        return False
    scale = 96 / img.height
    img = img.resize((max(8, int(img.width * scale)), 96), Image.BOX)
    tmp = out + ".tmp.png"
    img.save(tmp)
    if opaque_ratio(tmp) > 0.10:
        os.replace(tmp, out)
        return True
    os.remove(tmp)
    return False

def repair(fname):
    stem = fname[:-4]
    raw = os.path.join(RAWS, fname)
    out = os.path.join(SPRITES, fname)
    # 1) tighter reprocess of the existing raw (never overwrites with garbage)
    if os.path.exists(raw):
        img = ga.remove_bg(Image.open(raw), tol=22)
        img = ga.crop_content(img)
        if _try_result(img, out):
            print("  fixed by tighter bg-removal:", fname)
            return True
    # 2) regenerate; retry on black/blank duds with shifted seeds
    base, view = base_and_view(fname)
    prompt = ga.CHARACTERS.get(base)
    if prompt is None:
        print("  no prompt for", base)
        return False
    if view == "back":
        prompt = prompt.replace("facing viewer", "").replace("side profile", "") + BACK_STRONG
    elif view == "side":
        prompt = prompt.replace("facing viewer", "in full side profile view facing left")
    elif view == "side_r":
        prompt = prompt.replace("facing viewer", "in full side profile view facing right")                        .replace("side profile", "in full side profile view facing right")
    for attempt in range(3):
        print("  regenerating (%d):" % (attempt + 1), fname)
        data = ga.gen(prompt + ga.CHAR_SUFFIX, 768, 1024,
                      seed=(abs(hash(stem)) + 1000 + attempt * 7717) % 99999)
        open(raw, "wb").write(data)
        # black-dud detection: retry immediately instead of processing garbage
        probe = Image.open(raw).convert("L").resize((32, 32))
        pdata = list(probe.get_flattened_data()) if hasattr(probe, "get_flattened_data") else list(probe.getdata())
        if sum(pdata) / len(pdata) < 10:
            print("    black dud, retrying")
            continue
        img = ga.remove_bg(Image.open(raw), tol=38)
        img = ga.crop_content(img)
        if _try_result(img, out):
            return True
    print("  GAVE UP:", fname)
    return False

def main():
    force = sys.argv[1:] # explicit filenames to force-regen (e.g. the_deacon_back.png)
    print("sprite QA sweep:")
    bad = []
    for f in sorted(os.listdir(SPRITES)):
        if not f.endswith(".png"):
            continue
        r = opaque_ratio(os.path.join(SPRITES, f))
        flag = ""
        if r < 0.10 or f in force:
            flag = " REPAIR"
            bad.append(f)
        print("  %-28s opaque %4.0f%%%s" % (f, r * 100, flag))
    for f in bad:
        if f in force and os.path.exists(os.path.join(RAWS, f)):
            os.remove(os.path.join(RAWS, f)) # force = full regen, not reprocess
        repair(f)
    print("repaired %d sprite(s)" % len(bad))

if __name__ == "__main__":
    main()
