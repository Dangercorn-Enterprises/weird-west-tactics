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

**OPEN sub-decisions (Tim's calls — feel-changing):**
1. **Spotter or blind toss?** Does lobbing over a hill require a friendly unit
   with LOS to the target (BattleTech indirect doctrine — rewards fire-support
   positioning), or can anyone blind-toss with a scatter/drift penalty?
2. **High ground sees over?** Should standing on high terrain (h2) extend sight
   OVER lower cover (h1) — making the ridge the king position? (Calder rec: yes.)
3. **Does the AI lob too?** Enemy dynamite-throwers arcing over cover at the
   player — symmetric and cool, but needs AI no-LOS targeting. In or out for v1?

**Next:** on sub-decisions → Calder prototypes the C milestone (raycast LOS on
the height grid) for playtest, then layers the lob. Balance re-run via the
parity harness after.
