#!/usr/bin/env python
# =============================================================================
# DUSTFALL — WORLDMAP COMPOSER
# Builds the campaign map CARTOGRAPHICALLY from the real node graph, RDR2-map
# style: aged parchment + hand-inked terrain stamps (AI-generated), true
# Pacific coastline west of the coastal cities, terrain regions, dotted trails
# along the actual edges, and every city glyphed and NAMED (Special Elite).
# Geography matches gameplay because both read the same normalized coords.
# Inputs: assets_raw/map/*.png (tools/gen_assets.py-style generations)
# Output: godot/assets/scenes/worldmap.png
# The node mapping here MUST match worldmap.gd _node_pos: x: 0.06+0.88x, y: 0.08+0.84y
# =============================================================================
import io, os, json, math, random
from PIL import Image, ImageDraw, ImageFont, ImageEnhance

os.chdir(os.path.join(os.path.dirname(__file__), ".."))
W, H = 1344, 768
INK = (74, 48, 22)
INK_SOFT = (104, 72, 38)
OCEAN = (196, 178, 142)

design = json.load(io.open("godot/data/design.json", encoding="utf-8"))
nodes = {n["id"]: n for n in design["world_nodes"]}
edges = design["world_edges"]

def pos(n):
    return ((0.06 + n["x"] * 0.88) * W, (0.08 + n["y"] * 0.84) * H)

# ---- base parchment ----------------------------------------------------------
base = Image.open("assets_raw/map/parchment_blank.png").convert("RGB").resize((W, H))
base = ImageEnhance.Color(base).enhance(0.9)
draw = ImageDraw.Draw(base, "RGBA")

# ---- stamps (bg-removed, sepia, scalable) --------------------------------------
def load_stamp(name, height):
    img = Image.open("assets_raw/map/%s.png" % name).convert("RGBA")
    px = img.load()
    w, h = img.size
    # white-out: anything bright becomes transparent (ink drawings on white)
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            lum = (r + g + b) / 3
            if lum > 210:
                px[x, y] = (0, 0, 0, 0)
            else:
                alpha = int(min(255, (230 - lum) * 1.6))
                px[x, y] = (INK[0], INK[1], INK[2], alpha)
    bbox = img.getbbox()
    if bbox:
        img = img.crop(bbox)
    scale = height / img.height
    return img.resize((max(4, int(img.width * scale)), height), Image.LANCZOS)

def stamp_quality_ok(img_s):
    # a good ink stamp is mostly transparent; filled squares are rejects
    a = img_s.getchannel("A")
    opaque = sum(1 for v in a.getdata() if v > 60)
    return opaque / (img_s.width * img_s.height) < 0.55

mountains = load_stamp("stamp_mountains", 56)
mesa = load_stamp("stamp_mesa", 40)
if not stamp_quality_ok(mesa):
    print("WARN: mesa stamp rejected (filled square) — substituting mountains")
    mesa = mountains.resize((int(mountains.width * 0.7), int(mountains.height * 0.7)), Image.LANCZOS)
pines = load_stamp("stamp_pines", 44)
cactus = load_stamp("stamp_cactus", 34)
compass = load_stamp("stamp_compass", 130)

def stamp(img_s, x, y, scale=1.0):
    s = img_s if scale == 1.0 else img_s.resize(
        (max(3, int(img_s.width * scale)), max(3, int(img_s.height * scale))), Image.LANCZOS)
    base.paste(s, (int(x - s.width / 2), int(y - s.height / 2)), s)

rng = random.Random(1887)

# ---- Pacific coastline: west of the coastal city column -------------------------
# coastal anchors (real-geography nodes), coast runs slightly west of them
coast_ids = ["portland", "sanfran", "losangeles", "sandiego"]
anchors = []
for cid in coast_ids:
    if cid in nodes:
        x, y = pos(nodes[cid])
        anchors.append((x - 26, y))
anchors.sort(key=lambda p: p[1])
# extend to top/bottom of map
coast = [(anchors[0][0] - 14, 0)] + anchors + [(anchors[-1][0] + 30, H)]
# smooth polyline with wobble
pts = []
for i in range(len(coast) - 1):
    (x0, y0), (x1, y1) = coast[i], coast[i + 1]
    seg = max(2, int(abs(y1 - y0) / 26))
    for t in range(seg):
        f = t / seg
        pts.append((x0 + (x1 - x0) * f + rng.uniform(-7, 7), y0 + (y1 - y0) * f))
pts.append(coast[-1])
# ocean wash (everything west of the coast)
ocean_poly = [(0, 0)] + pts + [(0, H)]
draw.polygon(ocean_poly, fill=OCEAN + (110,))
# hatching along the shore
draw.line(pts, fill=INK + (220,), width=3)
for i in range(0, len(pts) - 1, 2):
    x, y = pts[i]
    draw.line([(x - 10, y + 3), (x - 3, y + 1)], fill=INK_SOFT + (150,), width=1)

# ---- terrain regions (northern pines, central/eastern ranges, southern desert) ---
def scatter(img_s, cx, cy, rx, ry, count, smin=0.6, smax=1.1, avoid_west_of_coast=True):
    for _ in range(count):
        x = cx + rng.uniform(-rx, rx)
        y = cy + rng.uniform(-ry, ry)
        if x < 40 or x > W - 40 or y < 60 or y > H - 40:
            continue
        stamp(img_s, x, y, rng.uniform(smin, smax))

# Oregon/N.California pines (top-left quadrant, east of the coast)
scatter(pines, W * 0.22, H * 0.13, W * 0.10, H * 0.07, 7)
# Sierra Nevada ridge (between the coast column and Nevada nodes)
for i in range(6):
    stamp(mountains, W * 0.20 + i * 26 + rng.uniform(-6, 6), H * (0.22 + i * 0.085), rng.uniform(0.7, 1.0))
# Rockies-ish ranges to the northeast (Salt Lake / Denver longitude)
for i in range(7):
    stamp(mountains, W * (0.52 + i * 0.045), H * (0.14 + (i % 3) * 0.07) + rng.uniform(-8, 8), rng.uniform(0.75, 1.05))
# southwestern mesas + cacti (the big desert belt)
scatter(mesa, W * 0.42, H * 0.58, W * 0.16, H * 0.14, 8)
scatter(cactus, W * 0.36, H * 0.74, W * 0.20, H * 0.12, 10)
scatter(cactus, W * 0.62, H * 0.66, W * 0.14, H * 0.12, 7)
scatter(mesa, W * 0.72, H * 0.44, W * 0.10, H * 0.10, 5)

# ---- Colorado river: from the Rockies southwest to the gulf ----------------------
river = []
rx, ry = W * 0.56, H * 0.30
for i in range(26):
    river.append((rx, ry))
    rx -= rng.uniform(2, 14)
    ry += rng.uniform(8, 20)
river = [(x, y) for x, y in river if y < H - 30]
draw.line(river, fill=INK_SOFT + (170,), width=3)

# ---- trails along the REAL edge graph ---------------------------------------------
def dotted(a, b, risk):
    ax, ay = a
    bx, by = b
    dist = math.hypot(bx - ax, by - ay)
    step = 10 if risk >= 3 else 8
    dots = max(2, int(dist / step))
    for i in range(dots + 1):
        t = i / dots
        x, y = ax + (bx - ax) * t, ay + (by - ay) * t
        r = 1.5 if risk >= 2 else 2.0
        draw.ellipse([x - r, y - r, x + r, y + r],
                     fill=(INK_SOFT if risk >= 3 else INK) + (235,))

for e in edges:
    a, b = nodes.get(e[0]), nodes.get(e[1])
    if a and b:
        dotted(pos(a), pos(b), e[2] if len(e) > 2 else 2)

# ---- cities: glyph + NAME -----------------------------------------------------------
font = ImageFont.truetype("godot/assets/fonts/SpecialElite-Regular.ttf", 15)
font_small = ImageFont.truetype("godot/assets/fonts/SpecialElite-Regular.ttf", 12)
placed = []  # label rects already drawn (collision avoidance)
def overlaps(rect):
    for o in placed:
        if rect[0] < o[2] and rect[2] > o[0] and rect[1] < o[3] and rect[3] > o[1]:
            return True
    return False
for n in sorted(nodes.values(), key=lambda m: (m["y"], m["x"])):
    x, y = pos(n)
    tier = int(n.get("tier", 1))
    s = 4 + tier * 2
    draw.rectangle([x - s, y - s * 0.55, x + s, y + s * 0.75], fill=(52, 34, 16), outline=(26, 17, 8))
    draw.polygon([(x - s - 1, y - s * 0.55), (x, y - s - 3), (x + s + 1, y - s * 0.55)], fill=(84, 52, 24))
    name = str(n["name"])
    f = font if tier >= 2 else font_small
    tw = draw.textlength(name, font=f)
    tx = min(max(4, x - tw / 2), W - tw - 4)
    ty = y + s + 2
    rect = (tx - 2, ty - 1, tx + tw + 2, ty + f.size + 1)
    tries = 0
    while overlaps(rect) and tries < 6:
        ty += f.size + 3  # slide down until the shelf is free
        rect = (tx - 2, ty - 1, tx + tw + 2, ty + f.size + 1)
        tries += 1
    placed.append(rect)
    # parchment halo so names stay legible over terrain
    draw.rectangle(list(rect), fill=(222, 203, 165, 170))
    draw.text((tx, ty), name, font=f, fill=INK + (255,))
    if ty > y + s + 3:  # leader tick when a label had to slide
        draw.line([(x, y + s + 1), (x, ty)], fill=INK_SOFT + (160,), width=1)

# ---- furniture: compass, title cartouche, weathered edges ---------------------------
stamp(compass, W * 0.925, H * 0.135, 1.0)
title_font = ImageFont.truetype("godot/assets/fonts/Rye-Regular.ttf", 30)
title = "THE ASHEN FRONTIER"
tw = draw.textlength(title, font=title_font)
cx = W * 0.5 - tw / 2
draw.rectangle([cx - 22, 14, cx + tw + 22, 62], fill=(222, 203, 165, 190), outline=INK + (255,), width=2)
draw.text((cx, 22), title, font=title_font, fill=INK + (255,))
ocean_font = ImageFont.truetype("godot/assets/fonts/SpecialElite-Regular.ttf", 18)
draw.text((14, H * 0.44), "P\nA\nC\nI\nF\nI\nC", font=ocean_font, fill=INK_SOFT + (200,), spacing=4)
# edge burn vignette
for i in range(26):
    a = int(90 * (1 - i / 26))
    draw.rectangle([i, i, W - 1 - i, H - 1 - i], outline=(30, 18, 8, a))

base.save("godot/assets/scenes/worldmap.png")
print("cartographic worldmap composed:", len(nodes), "cities named,", len(edges), "trails")
