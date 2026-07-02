# DUSTFALL — Art Stylebook (v1.3, first pass)

This is the living style reference for all Dustfall art. **First pass generated
2026-07-01** via NVIDIA NIM `black-forest-labs/flux.1-dev` (free tier) +
PIL post-processing. Every asset regenerates from `tools/gen_assets.py`
(idempotent — delete a PNG under `godot/assets/` to redo it; raws in
`assets_raw/`). Full prompts live in that script; treat it as part of this book.

## The look
**"Sun-scorched noir"** — FFT: Ivalice Chronicles presentation over weird-west
americana. Warm key light, deep umber shadows, brass accents; **teal is
reserved for the supernatural** (Ashfall, spirits, the Hollow).

## Palette anchors (from the Ashlands palette, src/sprites.js)
| Use | Hex |
|---|---|
| Ink outline | `#120c05` |
| Duster leather | `#6b4226` / highlight `#936037` |
| Denim | `#4a6080` |
| Brass/amber | `#d4a843` |
| Blood | `#c0392b` |
| Ashfall teal | `#4ecdc4` |
| Parchment | `#d4c5a9` |
| Hex purple | `#9a6ab8` |

## Prompt formulas
- **Pixel assets** (sprites, tiles): `<subject>, plain solid white background
  (sprites only), 16-bit SNES pixel art, crisp chunky pixels, dark warm ink
  outlines, weird west aesthetic, warm umber ochre and brass palette with teal accents`
- **Painted scenes** (interiors, vistas, map): `<subject>, painterly concept
  art, weird western americana, warm dusk light, deep umber shadows, brass and
  teal accents, moody, high detail`
- Character sprites: always `full body ... standing idle facing viewer, single
  character centered, no text`
- Flux quirks learned: sizes must be one of 768–1344 in steps of 64; the word
  "blood-red" can produce all-black output (safety dud) — use "orange/golden";
  always brightness-check outputs (`mean < 8` = regenerate with a new seed).

## Post-processing pipeline (tools/gen_assets.py)
- **Tiles**: generate 1024² → **center-crop 55%** (kills baked-in border
  vignettes that read as per-tile rings) → BOX-resize to 128² → NEAREST filter
  in-engine.
- **Sprites**: generate 768×1024 on white → corner flood-fill background
  removal (tol 38) → content crop (+6px pad) → BOX-resize to 96px tall.
  In-engine `pixel_size` normalizes world height to 1.35 tiles.
- **Scenes**: 1344×768, kept full-res; Godot letterboxes (`stretch_mode` 6).

## Asset inventory (first pass — all generated, status noted)
| Set | Assets | Status |
|---|---|---|
| Tiles | mesa/canyon/town/boneyard/foundry/hollow tops + cliff side | ✅ in-engine; seams acceptable, true seamless variants = pass 2 |
| Party sprites | 6 archetypes | ✅ strong (gunslinger is the benchmark) |
| Enemy sprites | 10 regulars + 5 bosses | ✅ strong; single idle pose only |
| Interiors | saloon, outfitter, shrine, forge, stable, marshal, doc | ✅ shown per-tab in town ("shop art") |
| Town exterior | town_street | ✅ town-menu backdrop |
| Worldmap | parchment frontier territory | ✅ RDR2-flavor; node graph overlaid |
| Title/ending | sunset riders vista | ✅ |

## Tools
- **Workhorse (free):** NVIDIA NIM flux.1-dev via tools/gen_assets.py.
- **Approved upgrade path:** [sorceress.games](https://sorceress.games/) — Tim OK'd a one-time fee for game asset generation (2026-07-01). Use it for the pass-3 items below (facing/walk sprite sheets especially — consistency across frames is where flux struggles). Tim sets up the account/payment; prompts + palette in this book carry over.

## Pass 2 — DONE 2026-07-01
- ✅ 9 prop sprites billboarded as battle cover (crate/barrel/cactus/rock/grave/bone/pipe/ember/spire)
- ✅ UI theme: parchment/brass, Rye + Special Elite bundled (ui_theme.gd)
- ✅ Damage floaters + hit flash (core on_damage hook), blob ground shadows, 2.1-tile bosses
- ✅ Tiles seam-blended (edge cross-fade)
- ✅ Trail network + settlement glyphs baked into worldmap art at true node positions

## Known gaps → pass 3 (sorceress.games territory)
1. Sprites have one idle pose — need 4 facings + walk/attack frame sheets
   (frame-to-frame consistency is where flux struggles; use sorceress).
2. Tile sets: 3 variants per biome for less repetition; true tiling textures.
3. Battle animations: attack lunge/recoil tweens, projectile tracers, AoE bursts.
4. Ambient audio port (the web build's synth design → AudioStreamGenerator or stems).

## Rules (carried from sprites.js, still binding)
- Every sprite must be **screenshot-verified in-engine** before it's "done".
- One mod per rider; teal = supernatural only; when in doubt, darker + warmer.
