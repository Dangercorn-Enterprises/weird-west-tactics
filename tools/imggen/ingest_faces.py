#!/usr/bin/env python
# forge-imggen face ingest — pile of raw photos -> clean face-centered training
# crops. Handles sideways/rotated photos (tries all 4 orientations) and detects
# on a downscaled copy (robust + fast). Commercial-clean (OpenCV YuNet Apache-2.0).
# Usage: python ingest_faces.py <raw_dir> <out_dir> [min_face_px]
import glob
import os
import sys

import cv2
import numpy as np
from PIL import Image, ImageOps

RAW, OUT = sys.argv[1], sys.argv[2]
MIN_FACE = int(sys.argv[3]) if len(sys.argv) > 3 else 90
MODEL = "/data/forge-imggen/models/yunet.onnx"
RES = 768
PAD = 0.7
DET_MAX = 1024  # detect on a copy no larger than this (YuNet likes normal-scale faces)
os.makedirs(OUT, exist_ok=True)
det = cv2.FaceDetectorYN.create(MODEL, "", (320, 320), score_threshold=0.55)


def best_face(img):
    """Return (score, x, y, w, h) of the strongest face in full-res coords, or None."""
    W, H = img.size
    scale = min(1.0, DET_MAX / max(W, H))
    small = img.resize((max(1, int(W * scale)), max(1, int(H * scale)))) if scale < 1 else img
    bgr = cv2.cvtColor(np.array(small), cv2.COLOR_RGB2BGR)
    det.setInputSize((small.size[0], small.size[1]))
    _, faces = det.detect(bgr)
    if faces is None or len(faces) == 0:
        return None
    f = max(faces, key=lambda fb: fb[2] * fb[3])
    inv = 1.0 / scale
    return (float(f[14]), f[0] * inv, f[1] * inv, f[2] * inv, f[3] * inv)


kept, skipped = 0, []
for path in sorted(glob.glob(os.path.join(RAW, "*"))):
    if os.path.isdir(path):
        continue
    try:
        base = ImageOps.exif_transpose(Image.open(path)).convert("RGB")
    except Exception:
        skipped.append((os.path.basename(path), "unreadable")); continue
    # try all 4 orientations; keep the rotation whose best face scores highest
    best = None  # (score, rot_img, x, y, w, h)
    for rot in (0, 90, 180, 270):
        rimg = base.rotate(rot, expand=True) if rot else base
        bf = best_face(rimg)
        if bf and (best is None or bf[0] > best[0]):
            best = (bf[0], rimg, bf[1], bf[2], bf[3], bf[4])
    if best is None:
        skipped.append((os.path.basename(path), "no face (any rotation)")); continue
    score, rimg, x, y, w, h = best
    if max(w, h) < MIN_FACE:
        skipped.append((os.path.basename(path), "face too small %dx%d" % (int(w), int(h)))); continue
    Wr, Hr = rimg.size
    cx, cy = x + w / 2, y + h / 2
    # square crop of REAL content (no black bars): clamp side to image, shift inside
    s = int(min(max(w, h) * (1 + 2 * PAD), Wr, Hr))
    L = int(max(0, min(cx - s / 2, Wr - s)))
    T = int(max(0, min(cy - s / 2, Hr - s)))
    crop = rimg.crop((L, T, L + s, T + s))
    crop.resize((RES, RES), Image.LANCZOS).save(os.path.join(OUT, "face_%02d.jpg" % kept), quality=94)
    kept += 1

print("CROPPED %d  (skipped %d)" % (kept, len(skipped)), flush=True)
for name, why in skipped:
    print("  skip:", name, "-", why)
