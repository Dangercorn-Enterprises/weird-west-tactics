# ANIMATION FRAMES — Lane C brief (2026-10-08, for Tim's pick)

*Where the art stands, what the engine now does with frames, three ways to
make them, and the pick I need from you. Receipts: godot/STYLEBOOK.md "pass 3",
tools/gen_walk_pilot.py (written 2026-07, never produced a sheet), Lane A feel
pass (commit 5d488f2), Lane C consumer (this commit).*

## Where it stands
- 21 characters x 4 facings = 84 idle sprites, all real art (flux, 2026-07-01).
  No walk, attack or death frames exist. `tools/gen_walk_pilot.py` exists and
  produced nothing (no `assets_raw/walk_pilot/`).
- Motion today is procedural (Lane A): tile-by-tile hop, lunge + recoil,
  squash-and-fade death, tracers, muzzle flash, blast burst. It reads fine;
  it is the floor, not the ceiling.
- The Steam trailer is blocked on walk cycles (STEAM_PAGE.md checklist).

## What the engine does now (shipped with this brief, zero art required)
`battle.gd` loads optional sheets per character and view:
`assets/sprites/<arch>_<view>_walk{i}.png` and `<arch>_<view>_attack{i}.png`
(i from 0, any count, views side / side_r / front / back). Fallback chain:
side_r -> side (mirrored) -> idle pose, so one side sheet per character is
enough to start. The walk tween shows two frames per tile step (0.13 s/tile,
about 15 fps) and shrinks the hop to a whisper (feet carry the motion); the
lunge shows attack frame 0 on the push and the last frame on the recoil.
Drop PNGs in, nothing else changes. `feel_test.gd` proves it with synthetic
frames.

## Frame spec (what any pipeline must deliver)
| anim | frames | views to ship first | size | notes |
|---|---|---|---|---|
| walk | 4 (6 if cheap) | side (mirrored for side_r) | 96 px tall, bottom-aligned, transparent bg | same palette + outline weight as the idle; contact pose on frame 0 |
| attack | 2 | side | same | frame 0 = raise/aim, frame 1 = recoil/flash |
| death | 0 | — | — | the squash-and-fade already reads; frames later if ever |
| front/back walk | 4 | later | same | only matters when the camera is square-on; side carries 70% of shots |

Budget for the first pass: 21 characters x (4 walk + 2 attack) side frames
= 126 frames = 21 sheets (one sheet per character, all frames in one image
so the character stays consistent).

## Three ways to make them
**A. Local sheet-in-one-image (free; the pilot script).** `gen_walk_pilot.py`
asks the fleet SDXL (Huginn :8710, flux on NIM as fallback) for one
horizontal sheet, slices by white gaps, scales + bottom-aligns. Consistency
across frames is exactly where flux/SDXL struggle (STYLEBOOK says so). Needs
the fleet reachable (not today) or the NIM key in the environment.
+ free, already written, one command per character. − coin-flip quality;
expect to regenerate; may never hit the bar for the 5 bosses.

**B. sorceress.games (approved paid path, STYLEBOOK 2026-07-01).** Purpose-
built for sprite sheets; frame-to-frame consistency is the product. You set
up the account; the prompts and palette in the stylebook carry over; the
engine consumes the same PNG naming. + the quality bar on the first try;
all 21 in an afternoon. − a fee; a new tool in the loop.

**C. Stay procedural + one "lean" frame generated from the idle (no AI).**
A script shears/offsets the idle sprite into a 2-frame step (lean forward,
lean back) and a 2-frame attack (raise, recoil) by pixel ops. + zero art
risk, zero cost, an hour. − it is a wobble, not a walk; buys little over the
hop.

## My recommendation
**A for the pilot, B for the pass.** Run the pilot on ONE character
(gunslinger, side, 4 frames) the first time the fleet is reachable; if the
QA strip passes your eye, run it across the roster; if it does not (my
bet: it will not for the bosses), take B for the roster and keep A for
throwaway extras. C is not worth the hour. Either way the engine side is
done; this is purely an art-pipeline pick.

## Decisions for you
1. Pipeline: A pilot first (recommended) / B straight away / C.
2. Frame count for the walk: 4 or 6.
3. Views: side only for the first pass (recommended) or all four.
