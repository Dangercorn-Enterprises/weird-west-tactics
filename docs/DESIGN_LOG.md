# DUSTFALL — Design Decision Log

*Running record of design sessions: what we decided and WHY. This is the combat
chapter of the design bible (matters for IP-shopping — documentation is product).
Tim = game director; decisions are his. Calder brings options + rationale.*

---

## Session #1 — Line-of-sight & fire doctrine (Pillar 2: "position wins wars")
**Date:** 2026-07-09 · **Status:** DIRECTION DECIDED, sub-decisions open

**Problem (from the 2026-07-09 systems audit):** no line-of-sight exists —
bullets pass straight through full-height mesas; cover is omnidirectional;
positioning has only 2 axes (range + height). For a game whose director is a
lifelong BattleTech fire-support player (Archer/ARC-2W), the terrain layer is
inert. See SYSTEMS_AUDIT_2026-07-09.md cluster 6.

**DECISION (Tim):** Option **B via C** —
- **C (milestone 1):** real LOS. Direct fire (all guns) is blocked by
  full-height terrain (h≥2), degraded by intervening cover. Terrain finally
  means something; the ridge, the mesa, the boulder all matter.
- **B (the doctrine layer), SCOPED DOWN:** indirect fire stays **RARE and
  characterful**, NOT a weapon class. The signature move is **lobbing a stick
  of dynamite over a hill to hit what's behind it** — "very western" (Tim).
  Home of the mechanic: thrown explosives (dynamite_bandit attack, ashfall_charge
  consumable); possibly supernatural "witch-sight" for hex tools. Guns do NOT
  arc. This is a flavor spike, not a system to build around.

**Rationale:** makes P2 real (sight lines, high ground, cover denial reward the
fire-support brain) without turning a western into an artillery game. The
dynamite-over-the-ridge is the hero beat.

**Sub-decisions — RESOLVED (Tim):**
1. **Lob = scatter without spotter, precise with.** BattleTech rules: a blind
   toss deviates (scatter roll → blast center drifts). A friendly unit with LOS
   to the target = spotter → the throw lands exactly where you want, no scatter.
   Fire-support positioning becomes teamwork.
2. **High ground is KING but a BEACON** — double-edged, not a free bonus:
   - Offense: +hit shooting down, and you see OVER lower cover ("I have the high
     ground"). Worth the climb.
   - Cost: you're skylined — high ground grants NO cover to the unit on it
     (exposed), so the ridge is a glass cannon. Take it for the shot, pay in risk.
3. **AI plays like a player — expected-value targeting.** It weighs a scattered
   low-% lob as usually bad, BUT raises its willingness when it sees GROUPED
   targets (AoE value climbs with clustering). "You miss 100% of the shots you
   don't take." Not "can I hit one guy" — it's EV incl. variance and AoE.

## Session #1b — Cover & terrain (spawned from #1; Pillar 2)
**Status:** DESIGNED, one keystone to confirm

**Cover model (XCOM×BattleTech, per Tim):** cover is a **chance to block, not
flat damage reduction**. Half cover = ~50% of the body shielded = ~50% chance
an incoming shot **hits the cover object instead of you**. This is directional
(protects from the covered side → flanking is real).

**KEYSTONE — CONFIRMED (Tim, 2026-07-09):** BT over XCOM — cover is a **block
roll**, not a to-hit penalty. Shots that would hit are absorbed by cover at the
cover's %; absorbed damage lands on the cover object.
⚠️ **Anti-exploit rule (Tim's explicit catch):** cover durability degrades ONLY
on successful absorbs of would-be HITS — never on outright missed shots.
Otherwise players strip cover for free by spamming low-accuracy shots at it.
Sequence per shot: roll to-hit FIRST → on hit, roll cover block → on block,
cover takes the damage. Misses touch nothing.

**Cover is DYNAMIC + material-typed:**
- **Heavy** (boulders, solid walls): effectively indestructible vs in-game
  munitions — you're "largely good."
- **Light** (trees, cactus, thin half-wall, upturned table): has cover-HP;
  degrades as it absorbs blocked hits; eventually breaks and stops being cover.
  Coverage is a live, destructible battlefield state.

**Difficult terrain:** terrain affects MOVEMENT — rough/rubble/brush tiles cost
double movement points (tabletop/XCOM staple). Positioning now has a real
economy: the safe path is the slow path.

**Build slicing (one system in hand before the next):**
- **Positioning v1 (prototype next):** raycast LOS (terrain blocks direct fire)
  + high-ground sees-over + high-ground-is-a-beacon (no cover up top) +
  directional cover-as-block-roll. Playtest in a skirmish.
- **Positioning v2:** material/destructible cover (cover-HP, light degrades) +
  difficult-terrain movement cost.
- **Doctrine layer:** lobbed dynamite (scatter/spotter) + AI expected-value lob.
- Re-run the parity/balance harness after each (combat-math changes void the
  green guarantee otherwise — audit cluster 6).
