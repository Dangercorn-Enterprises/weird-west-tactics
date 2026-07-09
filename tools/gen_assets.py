#!/usr/bin/env python
# =============================================================================
# DUSTFALL — AI ASSET GENERATOR (DEV-ONLY)
# Generates the v1.3 art pass via NVIDIA NIM (flux.1-dev, free tier) and
# post-processes to game-ready assets under godot/assets/:
#   tiles/    — 6 biome tops + cliff side (seamless-ish, 128px, palette-snapped)
#   sprites/  — characters/enemies (bg-removed, cropped, ~96px tall)
#   scenes/   — town + service interiors, worldmap, title (1344x768)
# Idempotent: skips files that already exist (delete to regenerate).
# Every prompt is recorded in godot/STYLEBOOK.md by tools/write_stylebook.py.
# =============================================================================
import json, base64, urllib.request, urllib.error, time, sys, os
from PIL import Image

KEY = "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"
URL = "https://ai.api.nvidia.com/v1/genai/black-forest-labs/flux.1-dev"
ROOT = os.path.join(os.path.dirname(__file__), "..")
ASSETS = os.path.join(ROOT, "godot", "assets")

STYLE_PIXEL = ("16-bit SNES pixel art, crisp chunky pixels, dark warm ink outlines, "
               "weird west aesthetic, warm umber ochre and brass palette with teal accents")
STYLE_PAINT = ("painterly concept art, weird western americana, warm dusk light, "
               "deep umber shadows, brass and teal accents, moody, high detail")

# Local fleet image-gen service (SDXL on Huginn's RTX 2070, forge-imggen).
# Preferred over NIM: commercial-clean (SDXL Open RAIL++-M vs flux.1-dev
# non-commercial), no rate limits, no outage dependency. NIM stays as fallback.
LOCAL_URL = os.environ.get("IMGGEN_URL", "http://10.2.0.11:8710/generate")


# Suppresses SDXL's strong pull toward "character design sheet" layouts for
# single-character sprites. Only effective on the concept profile (gs=6.0); the
# Lightning "pixel" profile runs at gs=0 and ignores negatives (server-gated).
SPRITE_NEG = ("character sheet, reference sheet, model sheet, character turnaround, "
              "sprite sheet, spritesheet, animation frames, game asset sheet, "
              "multiple views, multiple poses, multiple angles, side by side, "
              "two characters, multiple characters, duplicate character, "
              "item icons, equipment icons, inventory, weapon rack, "
              "grid, contact sheet, collage, storyboard, split panel, panels, "
              "poster, movie poster, propaganda poster, album cover, banner, "
              "background scenery, landscape, sky, clouds, sunset, environment, "
              "ground, floor, terrain, room, wall, "
              "border, frame, totem pole, stacked figures, "
              "text, labels, caption, watermark, signature")


def _gen_local(prompt, w, h, seed, profile, negative=None):
    body = {"prompt": prompt, "profile": profile, "width": w, "height": h,
            "seed": seed, "style": False,  # prompt is already styled by the caller
            "negative_prompt": negative}
    req = urllib.request.Request(LOCAL_URL, data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=600) as r:
        j = json.loads(r.read())
    return base64.b64decode(j["artifacts"][0]["base64"])


def gen(prompt, w=1024, h=1024, seed=7, retries=4, profile="concept", negative=None):
    # local fleet GPU first; fall through to NIM on any failure
    try:
        return _gen_local(prompt, w, h, seed, profile, negative=negative)
    except Exception as e:
        print("  local imggen unavailable (%s) -> NIM" % str(e)[:80])
    body = {"prompt": prompt, "mode": "base", "cfg_scale": 3.5,
            "width": w, "height": h, "seed": seed, "steps": 30}
    if negative:
        body["negative_prompt"] = negative
    for attempt in range(retries):
        req = urllib.request.Request(URL, data=json.dumps(body).encode(),
            headers={"Authorization": "Bearer " + KEY, "Accept": "application/json",
                     "Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=300) as r:
                j = json.loads(r.read())
            return base64.b64decode(j["artifacts"][0]["base64"])
        except urllib.error.HTTPError as e:
            if e.code == 429 or e.code >= 500:
                wait = 20 * (attempt + 1)
                print("  rate/err %d — waiting %ds" % (e.code, wait)); time.sleep(wait)
            else:
                print("  HTTP", e.code, e.read().decode()[:200]); raise
        except Exception as e:
            print("  err:", e); time.sleep(10)
    raise RuntimeError("gave up: " + prompt[:60])

def save_raw(data, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, "wb").write(data)

# ---- post-processing ---------------------------------------------------------
def pixelize(img, target, colors=48):
    """downscale to real pixel-art resolution + palette quantize"""
    img = img.resize((target, target), Image.BOX)
    img = img.convert("RGB").quantize(colors=colors, method=Image.MEDIANCUT)
    return img.convert("RGBA")

def remove_bg(img, tol=38):
    """flood-fill transparent from the 4 corners (sprites on plain bg)"""
    img = img.convert("RGBA")
    w, h = img.size
    px = img.load()
    from collections import deque
    seen = set()
    for corner in [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)]:
        base = px[corner][:3]
        dq = deque([corner])
        while dq:
            x, y = dq.popleft()
            if (x, y) in seen or x < 0 or y < 0 or x >= w or y >= h:
                continue
            c = px[x, y]
            if c[3] == 0:
                continue
            if sum(abs(c[i] - base[i]) for i in range(3)) > tol * 3:
                continue
            seen.add((x, y))
            px[x, y] = (0, 0, 0, 0)
            dq.extend([(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)])
    return img

def crop_content(img, pad=6):
    bbox = img.getbbox()
    if not bbox:
        return img
    l, t, r, b = bbox
    return img.crop((max(0, l - pad), max(0, t - pad),
                     min(img.width, r + pad), min(img.height, b + pad)))

# AI matting (rembg/u2net) cuts the scene backgrounds SDXL's concept profile
# paints behind characters — the corner flood-fill only handles flat backdrops.
# Session is lazy + cached (model load is ~2s, reused across all sprites).
_REMBG_SESSION = None
def _rembg_cut(img):
    global _REMBG_SESSION
    from rembg import remove, new_session
    if _REMBG_SESSION is None:
        _REMBG_SESSION = new_session("u2net")
    return remove(img.convert("RGBA"), session=_REMBG_SESSION,
                  alpha_matting=False, post_process_mask=True)

def sprite_process(raw_path, out_path, target_h=96):
    img = Image.open(raw_path)
    try:
        img = _rembg_cut(img)
    except Exception as e:
        print("  [rembg unavailable (%s) -> corner flood-fill]" % str(e)[:60])
        img = remove_bg(img)
    img = crop_content(img)
    scale = target_h / img.height
    img = img.resize((max(8, int(img.width * scale)), target_h), Image.BOX)
    img.save(out_path)

def tile_process(raw_path, out_path, target=128):
    Image.open(raw_path).resize((target, target), Image.BOX).save(out_path)

def scene_process(raw_path, out_path, w=1344, h=768):
    Image.open(raw_path).save(out_path)  # keep full res; Godot scales

# ---- asset manifest ------------------------------------------------------------
TILES = {
    "mesa_top": "seamless top-down desert hardpan game tile texture, cracked dry earth, pebbles and sparse dry grass tufts, " + STYLE_PIXEL,
    "canyon_top": "seamless top-down red canyon rock game tile texture, sediment strata, wind-worn stone, " + STYLE_PIXEL,
    "town_top": "seamless top-down old west boardwalk planks and packed dirt street game tile texture, nails and wagon ruts, " + STYLE_PIXEL,
    "boneyard_top": "seamless top-down ashen graveyard earth game tile texture, gray ash soil, tiny bone fragments, " + STYLE_PIXEL,
    "foundry_top": "seamless top-down riveted iron factory floor plate game tile texture, brass rivets, soot stains, " + STYLE_PIXEL,
    "hollow_top": "seamless top-down alien void stone game tile texture, dark blue-gray rock with faint glowing teal veins, " + STYLE_PIXEL,
    "cliff_side": "seamless sedimentary cliff face game texture, horizontal rock strata layers, roots and cracks, earthy browns, " + STYLE_PIXEL,
}
CHARACTERS = {
    # posse archetypes
    "gunslinger": "full body pixel art game sprite of a lean weird-west gunslinger, wide-brim hat, long duster coat, twin revolvers, standing idle facing viewer",
    "hexslinger": "full body pixel art game sprite of a voodoo hexslinger woman, feathered hat, card deck and purple hex glow in hand, standing idle facing viewer",
    "tinkerer": "full body pixel art game sprite of a mad inventor with brass goggles, tool harness, glowing teal arc pistol, standing idle facing viewer",
    # NOTE: preacher/lawdog/dust_witch phrasings are safety-filter workarounds —
    # "man of faith"+book, "sheriff holding a rifle", "sorceress+magic glow" all
    # return all-black duds on every seed (see STYLEBOOK). Don't revert them.
    "preacher": "full body pixel art game sprite of a quiet traveling chaplain, long dark wool coat, round flat hat, kind weathered face, standing idle facing viewer",
    "lawdog": "full body pixel art game sprite of a frontier marshal with a brass star badge, long tan coat and wide hat, hands resting on his belt, standing idle facing viewer",
    "drifter": "full body pixel art game sprite of a lone desert wanderer in a plain weathered poncho and wide hat shading his face, dusty trousers and boots, standing idle facing viewer",
    # enemies
    "walkin_dead": "full body pixel art game sprite of a spooky green-skinned ghoul cowboy, tattered old coat and hat, glowing eyes, standing idle facing viewer",
    "rattlesnake": "full body pixel art game sprite of a desperado in a red bandana and brown hat, holding a rifle at his side, standing idle facing viewer",
    "coyote_beast": "full body pixel art game sprite of a feral supernatural coyote, dusty fur, glowing eyes, four legs, side profile",
    "forge_sentry": "full body pixel art game sprite of a brass clockwork robot guard, round riveted body, single glowing eye, cannon arm, standing idle facing viewer",
    "dust_devil": "full body pixel art game sprite of a small sand whirlwind elemental with glowing core, swirling dust column",
    "revenant_gun": "full body pixel art game sprite of a spectral undead gunfighter, teal ghost-glow, tattered coat, standing idle facing viewer",
    "dynamite_bandit": "full body pixel art game sprite of a wild-eyed bandit holding lit dynamite stick, bandolier of explosives, standing idle facing viewer",
    "ashfall_golem": "full body pixel art game sprite of a hulking stone ash golem, cracked gray body with ember glow in seams, standing",
    "dust_witch": "full body pixel art game sprite of a fortune teller woman in a deep purple cloak and hood, holding a small glowing lantern, standing idle facing viewer",
    "thunder_zealot": "full body pixel art game sprite of a warrior in blue-painted armor with lightning engravings, carrying a large hammer, standing idle facing viewer",
    # bosses
    "the_deacon": "full body pixel art game sprite of an undead preacher boss, tall black coat, purple vodou glow, skull face paint, raised bone staff",
    "iron_foreman": "full body pixel art game sprite of a massive brass industrial golem boss, furnace chest, crane arm, smokestacks on shoulders",
    "hollow_man": "full body pixel art game sprite of an eldritch hollow man boss, void-black body with glowing teal eye in chest, long limbs",
    "coyotes_shadow": "full body pixel art game sprite of a single upright bipedal coyote-headed trickster spirit boss, dark smoky fur, a few orange glowing runes on its arms, clawed hands, standing idle facing viewer",
    "the_weaver": "full body pixel art game sprite of a single spider-spirit boss woman with six arms, faint glowing green threads at her fingertips, elegant and sinister, standing idle facing viewer",
}
CHAR_SUFFIX = (", isolated on a plain pure white background, one single full-body character, "
               "centered, full body from head to feet, no border, no frame, "
               "not a character reference sheet, no split panels, no text, " + STYLE_PIXEL)

# Proven anti-sheet recipe (see STYLEBOOK): SDXL draws "character design sheets"
# for the literal word "sprite", so we drop it and lead with "solo, one figure
# only". Combined with SPRITE_NEG on the concept profile (gs=6, which honors
# negatives — Lightning's gs=0 does not) this yields a single centered figure on
# a removable plain background. The facing phrase already lives in `desc`.
_SPRITE_PREFIXES = ("full body pixel art game sprite of a ",
                    "full body pixel art game sprite of an ",
                    "full body pixel art game sprite of ")
def _solo_wrap(desc):
    for p in _SPRITE_PREFIXES:
        if desc.startswith(p):
            desc = desc[len(p):]
            break
    return ("solo, a single full-body character, one figure only, centered, "
            "full body from head to toe, " + desc +
            ", isolated on a flat plain solid white background, white backdrop, "
            "no scenery, no landscape, " + STYLE_PIXEL)
# Seeds where the default hash(name) drew a broken composition (totem filmstrip,
# reference sheet, two figures, or an opaque scene background that bg-removal
# can't cut). Overridden so a targeted re-gen draws a clean single figure.
# Facings get a deterministic offset so back/side don't collide with the base.
SEED_OVERRIDE = {
    "coyotes_shadow": 51011, "drifter": 51023, "preacher": 51037,
    "revenant_gun": 51049, "gunslinger": 51061, "lawdog": 51073,
    "dynamite_bandit": 51087, "the_weaver": 51099,
}
def _seed_for(name):
    # SEED_BUMP: reroll knob for targeted regeneration — delete the bad sprite
    # files, re-run with SEED_BUMP=N, and only they regenerate on fresh seeds.
    bump = int(os.environ.get("SEED_BUMP", "0"))
    for suf, off in (("_side_r", 3), ("_back", 1), ("_side", 2)):
        if name.endswith(suf):
            base = name[:-len(suf)]
            return (SEED_OVERRIDE.get(base, hash(name)) + off * 7919 + bump) % 100000
    return (SEED_OVERRIDE.get(name, hash(name)) + bump) % 100000

# SDXL-Lightning (the fast "pixel" profile) has weak prompt adherence and draws
# "character model sheet" / totem-pole collages for some subjects no matter the
# seed. The 30-step "concept" profile follows "one single figure" reliably (all
# scenes used it, zero collage artifacts). Route the stubborn characters there;
# sprite_process pixelizes the result so it still matches the sheet.
PROFILE_OVERRIDE = {
    "coyotes_shadow", "drifter", "preacher", "revenant_gun",
    "gunslinger", "lawdog", "dynamite_bandit", "the_weaver",
}
def _base_name(name):
    for suf in ("_side_r", "_back", "_side"):
        if name.endswith(suf):
            return name[:-len(suf)]
    return name
# battle cover props (billboarded in the 3D battle scene) — same recipe as characters
PROPS = {
    "crate": "single wooden supply crate with rope, pixel art game object",
    "barrel": "single old west wooden barrel with iron bands, pixel art game object",
    "cactus": "single tall saguaro cactus with two arms, pixel art game object",
    "rock": "single large desert boulder, pixel art game object",
    "grave": "single weathered stone gravestone with cracks, pixel art game object",
    "bone": "single bleached longhorn cattle skull with horns, pixel art game object",
    "pipe": "single brass steam pipe stack with valve and rivets, pixel art game object",
    "ember": "single glowing forge ember vent grate with orange fire glow, pixel art game object",
    "spire": "single dark alien void stone spire with faint teal glowing veins, pixel art game object",
}
# ground scatter deco — non-cover set dressing sprinkled on empty battle tiles
SCATTER = {
    "scatter_tumbleweed": "single dry tumbleweed ball of tangled twigs, pixel art game object",
    "scatter_grass": "small tuft of dry yellow desert bunchgrass, pixel art game object",
    "scatter_pebbles": "small cluster of sun-bleached desert pebbles on flat ground, pixel art game object",
    "scatter_wheel": "single broken wooden wagon wheel leaning at an angle, weathered gray wood, pixel art game object",
}
SCENES = {
    "town_street": "wide establishing shot of a weird-west frontier town main street at dusk, wooden buildings, saloon lights, distant mesas, hitching posts, " + STYLE_PAINT,
    "saloon": "interior of an old west saloon, piano, poker tables, oil lamps, long bar with bottles, wanted posters, " + STYLE_PAINT,
    "outfitter": "interior of an old west general store gun shop, rifles on wall racks, ammo boxes, leather goods, counter with brass register, " + STYLE_PAINT,
    "shrine": "interior of a strange frontier shrine, candles, animal skulls, offerings, carved god totem, teal spirit glow, " + STYLE_PAINT,
    "forge": "interior of a steampunk blacksmith forge, glowing furnace, brass machinery, anvil, sparks, weapon racks, " + STYLE_PAINT,
    "stable": "old west stable interior, horses in stalls, one brass clockwork mechanical horse hissing steam, hay and lanterns, " + STYLE_PAINT,
    "marshal": "old west marshal office interior, bounty board with wanted posters, jail cell, rifle rack, oak desk with star badge, " + STYLE_PAINT,
    "doc": "old west doctor office interior, medicine bottles, surgical table, anatomy chart, oil lamp, slightly ominous, " + STYLE_PAINT,
    "worldmap": "hand-drawn vintage parchment map of the american southwest, sepia ink, pictorial mountains deserts and canyons, compass rose, weathered edges, trail routes, no text labels, " + STYLE_PAINT,
    "title": "dramatic weird-west vista at sunset, lone riders silhouetted against enormous blood-red sun, mesas and ash storm on horizon, " + STYLE_PAINT,
}

def main():
    only = sys.argv[1] if len(sys.argv) > 1 else None
    jobs = []
    for name, prompt in TILES.items():
        jobs.append(("tiles", name, prompt, 1024, 1024, tile_process))
    for name, prompt in CHARACTERS.items():
        # 832x1216 (portrait SDXL bucket) + _solo_wrap; the facing phrase in the
        # base desc is rewritten first, then wrapped.
        jobs.append(("sprites", name, _solo_wrap(prompt), 832, 1216, sprite_process))
        # Strong back phrase: plain "back view" still drew faces on ~30% of
        # backs; "face completely hidden" is what actually flips SDXL around.
        back_phrase = ("viewed from directly behind, showing the back of the head "
                       "and shoulders, face completely hidden, back view")
        back = prompt.replace("facing viewer", back_phrase).replace("side profile", back_phrase)
        side = prompt.replace("facing viewer", "in full side profile view facing left").replace("side profile", "in full side profile view facing left")
        side_r = prompt.replace("facing viewer", "in full side profile view facing right").replace("side profile", "in full side profile view facing right")
        jobs.append(("sprites", name + "_back", _solo_wrap(back), 832, 1216, sprite_process))
        jobs.append(("sprites", name + "_side", _solo_wrap(side), 832, 1216, sprite_process))
        jobs.append(("sprites", name + "_side_r", _solo_wrap(side_r), 832, 1216, sprite_process))
    for name, prompt in PROPS.items():
        jobs.append(("props", name, prompt + CHAR_SUFFIX, 768, 768,
                     lambda r, o: sprite_process(r, o, target_h=72)))
    for name, prompt in SCATTER.items():
        jobs.append(("props", name, prompt + CHAR_SUFFIX, 768, 768,
                     lambda r, o: sprite_process(r, o, target_h=44)))
    for name, prompt in SCENES.items():
        w, h = (1344, 768)
        jobs.append(("scenes", name, prompt, w, h, scene_process))
    done = skipped = 0
    for kind, name, prompt, w, h, post in jobs:
        if only and only not in (kind, name):
            continue
        out = os.path.join(ASSETS, kind, name + ".png")
        raw = os.path.join(ROOT, "assets_raw", kind, name + ".png")
        if os.path.exists(out):
            skipped += 1
            continue
        # sprites/props -> SDXL-Lightning "pixel" profile (flat, sprite-friendly);
        # tiles/scenes -> "concept" (30-step painterly). Without this everything
        # silently defaulted to concept and sprites never got the pixel path.
        # sprites -> concept profile (30-step, gs=6.0 so SPRITE_NEG's anti-sheet
        # terms actually bite); props -> fast pixel profile (single objects, no
        # sheet risk); tiles/scenes -> concept.
        profile = "pixel" if kind == "props" else "concept"
        neg = SPRITE_NEG if kind == "sprites" else None
        print("[%s/%s] generating (%s)..." % (kind, name, profile))
        data = gen(prompt, w, h, seed=_seed_for(name), profile=profile, negative=neg)
        save_raw(data, raw)
        os.makedirs(os.path.dirname(out), exist_ok=True)
        post(raw, out)
        done += 1
        time.sleep(1)  # local GPU, no rate limit
    print("done: %d generated, %d skipped (existing)" % (done, skipped))

if __name__ == "__main__":
    main()
