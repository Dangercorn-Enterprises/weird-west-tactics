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

**KEYSTONE — FINAL (Tim's spec, 2026-07-09): the BANDED SINGLE ROLL.**
Tim's design: cover gives a visible "cover bonus" (to-hit reduction), plus a
second resolution — if the shot WOULD have hit the bare target but was denied
by the cover bonus, the shot STRUCK THE COVER → cover is damaged.
One d100 roll, three outcome bands (example: aim 75, cover bonus 40):
  roll 1-35   → HIT UNIT        (hit chance with cover)
  roll 36-75  → STRIKES COVER   (the denied band — cover takes the damage)
  roll 76-100 → CLEAN MISS      (nothing is touched)
Properties: anti-exploit is inherent (pure misses never damage cover — only
shots that would have connected); mathematically equivalent to a to-hit-then-
block-roll but resolved in ONE roll; composes with the existing engine (cover
already subtracts from hit chance — we add the second threshold + cover damage
in the band). Directional: the bonus only applies vs shots crossing the
covered face.

**Degradation model (damage-class split, Calder rec pending Tim's pick):**
Small arms NEVER degrade heavy cover (no invisible 60-hit rock counters — a
6-8 turn fight never pays that off); explosives crack heavy (1-2 blasts) and
delete light. Light cover degrades from small-arms strikes-cover results
(~2-3) AND is destroyed outright by blasts. Legible 2x2: {light,heavy} x
{bullets,explosives}. Realism ("dozens of rounds could split rock") is served
by the explosive path instead of bookkeeping.

**OPEN (Tim): dynamite fuse.** His own trope — "the cowboy sees the lit stick
and moves" — implies FUSE-DELAY dynamite: lands on your turn, detonates at the
start of your next, enemies get one panicked move → dynamite becomes AREA
DENIAL / herding (flush them from cover into the gun line), not just damage.
Alt: instant boom (simpler, classic). Fuse-delay is more western AND more
fire-support; costs AI flee-the-blast work.

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
