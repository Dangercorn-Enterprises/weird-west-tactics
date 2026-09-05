# DUSTFALL: The Ashen Frontier — Steam page draft (v0.1, 2026-07-07)

*Working copy for the store page. Every claim below is grounded in shipped
design data (godot/data/design.json) or verified build behavior — numbers are
real, not aspirational. Target: $10 tier, HD-2D demo build by 7/12.
Tim: mark up freely; SHORT DESC has three options to pick from.*

---

## Basics

| Field | Value |
|---|---|
| Title | Dustfall: The Ashen Frontier |
| Developer / Publisher | Dangercorn Enterprises |
| Genre | Turn-Based Tactics, Tactical RPG |
| Price | $9.99 |
| Platforms | Windows (Godot 4.7, Vulkan) |
| Players | Single-player |
| Release shape | Free demo (Quick Skirmish + Act I opening) → full release |

## Short description (choose one, ≤300 chars)

1. *The sun died over the frontier and something older lit the lamps. Lead a
   posse of gunslingers, hexslingers, and worse across a weird-west wasteland —
   turn-based tactics where every shot, hex, and bargain with a god leaves a
   mark.*

2. *HD-2D turn-based tactics in a weird west that buried its dead shallow.
   Build a posse of six, court six dangerous gods, and shoot your way through
   the Ashfall — wounds persist, favor is currency, and the train to the Hollow
   only runs one way.*

3. *A tactics RPG about a frontier that came back wrong. Position, cover, and
   grit decide gunfights; six gods offer miracles with teeth. Chibi sprites,
   lit 3D dioramas, consequences.*

4. *(fleet draft — J5, 2026-07-09, corrected: no permadeath claim; the real
   mechanic is persistent wounds per game_state.gd:187)* — *Assemble a posse.
   Fight hexes, revenants, and iron golems on a cursed frontier. Carry every
   wound home. DUSTFALL is a turn-based tactical RPG of grid combat, scars
   that stick, and a branching campaign through a haunted Old West.*

> Fleet-draft lines worth stealing for marketing copy (J5, grounded-checked):
> "revenants wearing faces you buried" · "Each one is flesh and will, not a
> unit" · "watch the curse take root when the plan goes wrong". REJECTED from
> the same draft: all permadeath/"lose them forever"/"no reload" claims —
> factually wrong (wounds persist, fallen survive at 1 HP), would be
> refund-bait on a store page.

## About this game (long description)

**The Ashfall came down like snow that never melted, and the West got weird.**

Dustfall is a turn-based tactics RPG in the HD-2D style — crisp pixel-art
posse members over lit, rotatable 3D dioramas — set in a weird-west frontier
of dead mining towns, bone-choked badlands, and one train line that shouldn't
still be running.

**Build a posse worth burying.** Six archetypes — Gunslinger, Hexslinger,
Tinkerer, Preacher, Lawdog, Drifter — each with their own abilities, favored
stats, and bad habits. Recruit up to six; keep them alive if you can. Wounds
follow your crew out of battle, and the fallen crawl away at death's door
rather than into it.

**Fight like position matters.** Height, cover, and line of sight decide
gunfights. Statuses stack ugly — burn, bleed, hex, marked — and a hunkered
enemy is a wasted bullet. Fifteen enemy breeds with real temperaments: some
rush you, some hold the high ground, some don't care about you at all until
you're worth eating.

**Bargain with six gods who are all listening.** Coyote, Baron Samedi, Vulcan,
Perun, Anansi — and the Sleeper, who you'd best not wake. Favor is a currency:
earn it in blood, spend it on divine riders that turn a fight sideways.
Shrines bless; some prices aren't posted.

**Cross a frontier with 26 bad ideas on the map.** A 3-act campaign across
mesa, canyon, boomtown, boneyard, foundry, and the Hollow — six biomes, each
with its own board and its own weather of trouble, and five named bosses who
have been expecting you.

**Outfit for the country you're crossing.** Seven weapons, five armors, four
weapon mods, three mounts, and a satchel of consumables that all earn their
slot. A procedurally-synthesized western score — every gunshot, drone, and
saloon pluck generated, no two ambushes scored quite the same.

## Feature bullets (store sidebar)

- Turn-based tactical combat on lit 3D boards — height, cover, crits, and
  seven ways to bleed
- HD-2D: 4-direction pixel-art sprites over rotatable dioramas (Q/E turns the
  whole world)
- 6 playable archetypes, posses up to 6, wounds that persist between fights
- 6 gods, favor economy, divine riders — miracles with fine print
- 3-act campaign across 26 world nodes, 6 biomes, and 5 named boss showdowns
- 15 enemy breeds with distinct AI temperaments
- Gear that matters: 7 weapons, 5 armors, 4 mods, 3 mounts
- Fully synthesized soundtrack and SFX — the desert never repeats itself
- Quick Skirmish mode for a straight fight, no questions asked

## Tags (Steam, pick ~15)

Turn-Based Tactics · Tactical RPG · Strategy RPG · Western · Dark Fantasy ·
Pixel Graphics · Retro · Party-Based RPG · Turn-Based Combat · Singleplayer ·
Atmospheric · Stylized · Isometric · Difficult · Indie

## System requirements (draft)

- **Minimum:** Windows 10 64-bit · Vulkan 1.0-capable GPU · 4 GB RAM ·
  300 MB disk
- *(Godot 4.7 Forward+ renderer; the shipped build is a single ~116 MB exe.
  Verify minimum GPU claim on one low-end machine before publishing.)*

## AI-content disclosure (REQUIRED by Steam at submission)

Steam requires disclosure of AI-generated content. Honest wording:

> *Character sprites, tile textures, and scene illustrations were generated
> with Stable Diffusion XL 1.0 (self-hosted, Open RAIL++-M license) from
> hand-written prompts against a fixed style guide, then hand-curated and
> post-processed (AI background matting, palette snapping, pixel-resolution
> downscale). All game design, code, writing, and audio synthesis are
> original. No AI-generated content is created at runtime.*

*(2026-07-09: full asset set regenerated on self-hosted SDXL — the earlier
FLUX.1-dev assets were non-commercial-licensed and are gone from the tree;
every shipped image is now commercially clean.)*

> **ACCURACY FLAG 2026-09-04 (code-verified, must be resolved before
> submission):** the sentence above claims "palette snapping". The helper
> that does it (`pixelize`, tools/gen_assets.py, BOX downscale + median-cut
> quantize) is defined but never called: `sprite_process` does rembg/flood
> matting, crop, and a BOX resize only; `tile_process` is a BOX resize;
> `scene_process` saves at full resolution. No shipped asset was palette
> quantized. Before this disclosure is filed, either wire `pixelize` into
> the pipeline and regenerate, or reword the sentence to what was actually
> done (AI background matting, content crop, pixel-resolution downscale).
> A Steam disclosure that overstates the processing is a false statement.

## Screenshots — RECAPTURED 2026-09-04 from HEAD e441376 (docs/steam_screens/, 1920x1080)

All captured via the DUSTFALL_AUTOPILOT tour (run with --resolution 1920x1080; the project default is 720p). First set 2026-07-09 from the pre-July-10-rules build; six of eight recaptured 2026-09-04 from HEAD after the tour was reordered so shot_battle is taken with the intro card dismissed (shot_title and shot_creator came back byte-identical and were kept).
Store picks, in order: `shot_title` (vista + logo), `shot_creator` (Forge Your
Lead, 6 archetypes), `shot_battle_intro` (HD-2D diorama + story card),
`shot_worldmap` (parchment campaign map), `shot_town` (saloon services).
Extras: `shot_battle`, `shot_battle_rotated` (Q/E world turn), `shot_pause`.

## Store asset checklist (what still needs making)

*(Sizes verified live against the Steamworks store/library graphical asset
spec on 2026-09-04; the earlier from-memory sizes were the pre-2024 spec and
would be rejected at upload. Re-check partner.steamgames.com once more on
upload day. Rule for every store capsule: artwork, game name, and the
official subtitle ONLY, no other text, no awards, no review quotes.)*

**Store capsules (all required)**
- [ ] Header capsule 920×430 (title art exists: assets/scenes/title.png,
      needs logo lockup + crop)
- [ ] Small capsule 462×174 (Steam auto-derives the 120×45 and 184×69 sizes)
- [ ] Main capsule 1232×706
- [ ] Vertical capsule 748×896

**Library assets (all required, previously missing from this list)**
- [ ] Library capsule 600×900 (vertical, generate on forge-imggen, no longer
      NIM-blocked)
- [ ] Library header 920×430 (may reuse the store header)
- [ ] Library hero 3840×1240, keep the logo and key art inside the centered
      860×380 safe area (generate on forge-imggen, no longer NIM-blocked)
- [ ] Library logo 1280×720, transparent PNG, logo only

**Screenshots**
- [x] At least 5 screenshots, 1920×1080 minimum, 16:9, gameplay only (no
      concept art, no pre-rendered scenes, no marketing text). DONE
      2026-09-04, docs/steam_screens/ (8 shots, all in-engine, from HEAD e441376;
      title and creator unchanged since 2026-07-09)
- [ ] Trailer (30–60s) — screen-capture the autopilot tour as a placeholder
      cut; real trailer after walk-cycle art
- [x] Demo build depot — re-exported 2026-09-04 from HEAD 7575fc3 (the 2026-07-09 exes predated every July 10 rule): dist/dustfall-demo.exe (Act-I capped
      via "demo" feature tag) + dist/dustfall-hd2d.exe (full), both boot-tested

## Open questions for Tim

1. Short description: pick 1/2/3 (or blend).
2. "Dangercorn Enterprises" as the publisher name on Steam, or a games label
   (e.g. the sorceress.games account idea from 07-06)?
3. Demo scope: Quick Skirmish only, or Skirmish + Act I opening?
4. Steam Direct $100 fee + tax interview — ready to file when you are (needs
   the entity decision that also gates SBIR).
