# Dustfall Balance Findings — 2026-06-21
*From a verified run of `tools/balance_harness.js` (EXIT 0). Numbers are win-rates. NOT applied — surfaced for Tim's call on difficulty feel.*

Target bands: **story 70–85% · ambush 80–90% · boss 45–65%** (2-party; real play with abilities sits a bit above the floor).

## In band ✓
- Act 1 · The Deacon (boss): **60.8%** — good.

## Out of band (candidates for a balance pass)
- **Reckoning · Iron Foreman: 21.2%** — far too hard for 2 party (target 45–65%). The standout. (4-party = 96%, so it's a small-party brick wall, not globally broken.)
- Reckoning · The Weaver: **87.2%** — too easy for a boss.
- Reckoning · Hollow Man: **80.4%** — too easy for a boss.
- Ambush · trail T1 **95.1%**, wilderness T2 **91.1%** — a touch above the 80–90% band.
- Act 2/3 encounters: 96–100% — easy (may be intended for a geared late-game party).

## Suggested direction (your call — nothing changed)
- Iron Foreman: ~15–20% less HP/damage at 2-party, or lean on `DF.scaleEncounter` to scale by party size.
- Weaver / Hollow Man: nudge up ~10–15%.
- Ambushes: minor +5%.
- Re-run `node tools/balance_harness.js` after any change to confirm it lands back in band.

---
## APPLIED 2026-07-01 (Pass 3 of the v1.1 improvement loop) — verified 2000 runs, seed 1337
- Iron Foreman: hp 60→48, str 9→8, aim 65→63, dmg 7-12→6-10 → **54.1%** ✓
- The Weaver: hp 30→38, str 5→6, quick 5→6, aim 73→74, dmg 4-8→4-10 → **52.5%** ✓
- Hollow Man: hp 35→44, str 6→7, aim 74→76, wmax 9→11 → **52.0%** ✓
- Revenant Vanguard: dropped one walkin_dead from the comp → **79.3%** ✓ (was 65-66, below story band)
- Ambushes: rattlesnake hp 16→20 wmax 8→9, ashfall_golem hp 30→38 wmin 6→7, walkin_dead wmax 7→6, revenant_gun hp 18→16 aim 74→72, dynamite_bandit hp 14→12 → trail **90.1%**, wilderness **86.6%** ✓
- 4-party scaling clamps 1.2/1.1 → 1.35/1.2 (engine + harness) — full-posse story beats now bite (Act 3 heralds 73.7%, finale 82.9%)
- 4-party boss *reckonings* and Act 2 fights remain 97-100%: intended — replaying a broken boss with a grown posse should feel like a stomp.

## Pass 10 (2026-07-01): enemy AI behaviors wired + rebalance — verified 2000 runs, seed 1337
- sentry holds ground (+8 aim braced) · zealot berserks <50% HP (+10 aim, +2 wmax, ignores cover) · swarm rushes nearest · cover weights cover 2.5x · flank hunts the weakest rider globally.
- Knock-on retune: walkin_dead hp 16 wmax 7, rattlesnake back to hp 18 wmax 8 (cover AI made it deadlier), Vanguard comp = revenant_gun + walkin_dead + 2x dynamite_bandit.
- Final: Vanguard 75.6 ✓ · Deacon 46.8 ✓ · Foreman 63.8 ✓ · Weaver 52.9 ✓ · Hollow Man 49.7 ✓ · T2 ambush 87.5 ✓ · Heralds 73.4 ✓ · finale 80.5 ✓.
- T1 trail ambush representative comp reads 97.7% — random T1 draws span 56-98% by composition (2-snake draws are dangerous, melee-heavy draws are easy). Variance is intended for random encounters; not tuned further.
- NOTE: swarm +1 AP was tried and REVERTED (double-attacks in melee crashed Deacon to 24%). Don't retry without a melee AP cost rework.
