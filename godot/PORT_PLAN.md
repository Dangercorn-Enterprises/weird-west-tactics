# Dustfall — Godot 4 Port Plan (v1.3 →)

**Decision (2026-07-01, Tim):** move to a real engine for a Steam-marketable
($10-tier) HD-2D tactics game, with enough polish to shop the IP to a studio.
Engine: **Godot 4.7** (free/MIT, HD-2D-friendly, Steam export). Art: **AI-generated
sprite/tile sheets + hand cleanup** against the style guide below.

**Prime directive:** the web build (v1.2.1) stays playable throughout; `src/data.js`
remains the single source of design truth (exported via `node tools/export_data.js`);
every combat change must keep `node tools/parity_check.js` green so the balance
work (2000-run verified bands) carries over exactly.

## What exists now (Phase 0-1, done this session)
- `godot/` project scaffold (Godot 4.7, Forward+)
- `godot/data/design.json` + `sprites.json` — generated from data.js/sprites.js
- `godot/scripts/combat_core.gd` — faithful port of the harness math (hit/damage/
  reach BFS/statuses/AI temperaments/divine riders/boss phase/scaling/crits),
  seeded mulberry32 RNG
- `godot/tests/parity_test.gd` + `tools/parity_check.js` — headless Godot vs Node:
  exact unit-derivation asserts + win-rate parity within ±4 pts on 2000 runs
- `godot/scenes/battle.tscn/.gd` — interactive prototype: 3D board, ortho FFT
  camera with Q/E turns, billboard sprites from shared pixel data, click
  select/move/attack, Enter runs the CombatCore enemy phase

## Phases to full parity with the web game
1. **Battle feature-complete:** abilities menu + divines + items + hunker,
   biome boards from design.json (all 6), combat preview UI, floaters/particles,
   crit freeze-frame, blessing hook, wound writeback contract
2. **Campaign shell:** worldmap (nodes/edges/acts from worldmap_data.js — add it
   to the exporter), town services (saloon/outfitter/shrine/forge/stables/
   marshal/doc), save/load (Godot `user://` JSON, same shape as the web save)
3. **Audio:** port the synth design (AudioStreamGenerator) or replace with
   composed stems; keep the 5-mood scene map
4. **Art pass (AI-gen + cleanup, style guide below):** character sheets with
   4-direction idle/walk/attack frames, tile texture sets per biome, deco props,
   UI skin (parchment/brass per game.html palette)
5. **Ship:** Steam export templates, page assets, demo build

## HD-2D art style guide (for AI generation + cleanup)
- **Reference bar:** FFT: The Ivalice Chronicles / Octopath — chibi ~2.5 heads,
  crisp pixel sprites over lit 3D terrain
- **Sprite spec:** 32×40 px characters, 4 facings, dark warm ink outline
  (#120c05), max ~16 colors per sprite drawn from the Ashlands palette
  (see `src/sprites.js` SPRITE_PAL: duster leather #6b4226, denim #4a6080,
  brass #d4a843, ashfall teal #4ecdc4, blood #c0392b, bone #e8dcc8)
- **Tiles:** 48×48 px tops with beveled edge (lit top-left lip, shaded
  bottom-right), strata-banded sides; per-biome sets: mesa hardpan, canyon
  strata, town boardwalk, boneyard ash, foundry plate, hollow void
- **Mood:** sun-scorched noir — warm key light (#ffe0b0), deep umber shadows,
  teal reserved for the supernatural (Ashfall, the Hollow)
- **Rule carried from sprites.js:** every sprite added must be screenshot-
  verified in-engine before being called done

## Working agreements
- No forks/branches — everything on `main`; web build untouched under `src/`
- Run `npm test` (web) and `node tools/parity_check.js` (port) before committing
  combat changes
- Godot binary: winget `GodotEngine.GodotEngine` (4.7);
  console exe under `%LOCALAPPDATA%/Microsoft/WinGet/Packages/GodotEngine.*`
