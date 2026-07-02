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

## Known gaps → pass 2
1. Battle cover decos are still flat colored boxes — generate crate/cactus/
   grave/pipe/spire prop sprites and billboard them (same recipe as characters).
2. Sprites have one idle pose — need 4 facings + walk/attack frames
   (generate sheets, or animate via frame interpolation on the singles).
3. Worldmap node positions are geographic, art is fictional — consider
   generating the map FROM the node layout (img2img over a plotted guide).
4. Tile sets: 3 variants per biome for less repetition; true seamless tiling.
5. UI skin: parchment/brass theme (Godot Theme resource) to replace default
   gray Controls; the web build's Rye/Special Elite fonts.
6. Boss-scale sprites (Iron Foreman should tower ~2 tiles).

## Rules (carried from sprites.js, still binding)
- Every sprite must be **screenshot-verified in-engine** before it's "done".
- One mod per rider; teal = supernatural only; when in doubt, darker + warmer.
