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
