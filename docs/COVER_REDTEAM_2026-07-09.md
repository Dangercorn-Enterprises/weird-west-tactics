# Cover system — exploit red-team (Njord, grok-4.5, 2026-07-09)
# Commissioned before building Positioning v1. Calder's disposition appended.

1. TOP EXPLOITS
- Heavy-cover immortality (small arms): Park elites behind heavy. Small arms never degrade it; only rare explosives crack it. Dominates any infantry/small-arms mission — game-breaking.
- Always-hunker turtle: 1 AP hunker turns solid cover into a near-miss wall (40→60). Optimal every turn you stay put. Boring dominant line; fights become “hunker until explosives.”
- High-ground erasure of low cover: Elevation sees over low cover + hit bonus + you grant no cover to yourself but you delete the enemy’s common defense layer. First side to seize roof/ridge wins — dominant, often game-breaking on multi-level maps.
- Free-flank deletes the system: Directional cover is binary. If move AP lets you walk the corner without reaction threat, cover is a tax until someone flanks, then zero. Boring; map geometry > rules.
- Dynamite/spotter bypass: Lob ignores the banded block-roll, damages cover, scatter only if no friendly LOS. Spotter in safety + thrower behind hard LOS = delete light/heavy without ever rolling the cover band. Game-breaking if not truly rare / costly.
- Ablative light-cover soak: Light is 2–3 free “would-have-hit” shields. Cheap units or sequential swaps through the same waist-high wall farm free HP. Minor→boring attrition cheese.
- Elite-aim cover melt: High aim widens the “strike cover” band; best shooters are mandatory cover-saws even when they never tag flesh. Forces alpha-strike / focus-fire-cover-first every engagement — boring if always correct.
- Mutual heavy bunker stalemate: Both sides heavy + limited explosives = multi-turn no-trade staring contest until dynamite or a free flank. Boring / mission-stall.

2. FIXES
- Heavy immortality: Small arms can “chip” heavy on strike (slow: 4–6 strikes to crack, or only on crit-band). Or explosives not the sole answer — give 1 AP “breach” tool (shotgun/axe) that only works adjacent.
- Always-hunker: Hunker costs 1 AP and ends turn, or only works if you took no move, or grants the absorb boost but tags you “pinned posture” (easier to flank / -defense if flanked). Cap hunker bonus so it never erases the hit band entirely.
- High-ground erase: High ground sees over low cover only at short range, or low cover still grants partial bonus vs elevated (half bonus), or high ground units get a small inherent cover penalty only vs other elevated — pick one simple half-bonus rule.
- Free flank: Add overwatch/reaction fire (standard: reserve AP, snap shot on enter-LOS/move-in-band). Or flanking requires ending adjacent to covered face / rear arc, not just “any non-front ray.”
- Dynamite bypass: Dynamite still rolls a reduced cover band (or always risks scatter even with spotter), costs 2 AP + consumable, and damages thrower on mishap. Spotter LOS does not auto-perfect the throw — cut scatter only.
- Ablative soak: Cover strikes that don’t break still splash chip damage to the unit (small fixed), or light cover once struck becomes “unstable” (−bonus until repaired/abandoned).
- Elite melt / stalemate: Soft-cap strike band (excess aim above cover converts partly to crit/effect, not pure cover HP delete), and give a cheap “flush” order (smoke, flash, or forced reposition) so pure bunker is not the only answer.

3. NUMBERS TO WATCH
- Cover bonus % (e.g. 40): Too high → turtles and strike-farm; too low → cover is flavor text, always shoot the man.
- Hunker absorb boost and AP cost: Boost too high / cost too low → always hunker; boost too low → dead action.
- High-ground hit mod and “see over low”: Mod too high + full ignore low → roof always-correct; mod too low / no see-over → elevation pointless.
- Light-cover strikes-to-break (2–3): Too low → cover pops instantly, no decision; too high → light becomes fake heavy, fights stall.
- Heavy vs small-arms interaction (currently never): If truly never, explosives scarcity dictates whole meta; any chip rate must stay slow or heavy dies to rifle spam.
- Dynamite rarity, scatter, AP, and “ignores block-roll”: Too available / too clean → cover system optional; too weak → heavy immortality returns.
- Base AP pool vs hunker/shoot/move costs: If hunker+shoot fits every turn easily, turtle; if move-to-flank is cheap relative to shots, flanks trivialise cover.
- Aim distribution (grunt vs elite): Elite aim that massively widens strike band makes “shoot cover first” the only line; flat aim makes cover RNG-swingy.

4. ONE THING MISSING
Overwatch / reaction fire (reserve AP to punish entry into LOS or corner-cross). Without it, flanking is free movement math, directional cover never faces real risk, and the whole banded-cover game collapses into “walk around or wait for dynamite.”

---
## Calder disposition (which fixes land in v1)
BAKED INTO v1:
- High-ground HALVES enemy cover, does NOT erase it (Njord fix #3) — better than my 'negate'; roof still strong, not auto-win.
- Light cover degrades its BONUS per strike (0.2 decays toward 0), not 3 binary shields (Njord 'ablative soak' fix) — dynamic + anti-farm.
- Total cover_bonus capped so hunker can't erase the hit band (clamp already forces >=5% hit).
FLAGGED FOR TIM / v2 (not in v1):
- OVERWATCH/reaction fire = Njord's 'one thing missing' + load-bearing for flanking to matter. #1 v2 priority.
- Hunker-turtle economy: consider hunker ends-turn or no-move-required. Tim's call on hunker AP economy.
- Dynamite: even with spotter, keep some scatter risk + 2 AP + consumable so it's not a clean cover-delete (doctrine layer).
- Heavy cover stays bullet-immune (Tim's deliberate call); explosive availability is the tuning lever that stops heavy being auto-win.
