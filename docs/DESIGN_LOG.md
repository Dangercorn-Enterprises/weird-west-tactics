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
  > **CORRECTION 2026-09-04 (code-verified):** "degraded by intervening
  > cover" was NOT built. has_los (combat_core.gd) reads only tile height;
  > it never reads cover. Cover affects the shot only through the target's
  > own tile (cover_bonus), never through tiles along the line. The decision
  > text above stands as the decision; the mechanic remains unbuilt.
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

---
## Positioning v1 — BUILT (2026-07-09, commits 71385a9 + 2f8401e)
Shipped: LOS raycast (h>=2 blocks direct fire; high ground sees over), banded
single-roll cover (hit/strikes-cover/miss), high-ground halves target cover +
beacon (no cover on high tiles), hunker +0.20 capped at 0.60, point-blank
negates cover (v1 flank proxy), destructible LIGHT cover decaying its bonus,
heavy bullet-immune, explosives crack/delete cover; AI + player policy LOS-aware;
battle-scene FX (cover topples + dust puff on break). tests/positioning_test.gd
17/17. Battle boots clean.
> **CORRECTION 2026-09-04 (code-verified): "high ground sees over" is NOT
> shipped.** The has_los exception (combat_core.gd, the `att_h > def_h and
> wall_h <= att_h` branch) only fires when the attacker stands on a tile of
> h>=2, and reach() treats every h>=2 tile as impassable, so no unit can ever
> occupy one on any shipped board. The branch is dead code in practice. What
> IS live from the high-ground list: the shooter-higher-than-target cover
> halving (cover_bonus) and the beacon strip (defender on h>=1 gets no
> cover, hunker aside). The
> LOS raycast itself (h>=2 blocks direct fire) is live and unchanged.

**Balance shift (2000-run bot-vs-bot):** skirmish .99->.67, finale .84->.53,
foreman .62->.47 DOWN; vanguard .74->.81, deacon .52->.62, weaver .65->.70,
hollow .64->.67 UP. Unit derivations unchanged.
⚠️ **CAVEAT — do not retune off these:** the sim's scripted player bot cannot
USE the new tools (never seeks high ground, never flanks, never repositions for
LOS), so it eats the downsides without the upsides — win rates understate human
play. Tuning against a positionally-blind bot tunes the game for a bad player.
Real balance = a HUMAN playtest (Tim) + a positional bot policy. This is a
PLAYTEST gate.

**Deferred to v2 (Njord red-team priorities):** OVERWATCH/reaction fire (#1 —
makes flanking risky, load-bearing), full edge-directional cover, difficult
terrain (double MP), hunker-turtle economy (ends-turn/no-move), the dynamite
LOB doctrine (scatter/spotter). Njord's full report: docs/COVER_REDTEAM_2026-07-09.md.

---
## Sim instrument fixed — positional bot + NEW BASELINES (2026-07-09 night,
## commits 57eddf9 · f485756 · 0017e4f · 20119b2)

**What happened, in order:**
1. **God-swearing port regression FIXED** (audit clusters 4+5): party_to_unit
   now carries p['god'], so shrine Swear actually redirects the divine's favor
   pool, favor-on-win, and blessing alignment (web behavior restored). New
   tests/god_swear_test.gd 5/5 — the parity harness could never see this
   (mk_party has no god field).
2. **Parity was RED and nobody knew** — exactly the risk this log flagged:
   Positioning v1 went into the Godot core only; the Node harness still ran
   pre-v1 math (skirmish node 98.9 vs godot 67.3). v1 is now line-mirrored
   into balance_harness.js; the harness header names combat_core.gd as the
   canonical engine. Parity re-proven at Δ 0.0 pts on all 7 encounters —
   bit-exact, both engines consume identical RNG draw sequences (stronger
   than the old ±2.1pt statistical green).
3. **Interactive LOS truth** (battle.gd): the UI let the player PAY for
   LOS-blocked shots (2 AP basic fire logged as a fake "miss", ability AP,
   even the once-per-fight divine + favor) while the hover preview showed
   invented odds. Now: refusal at zero cost ("No line of sight."), preview
   says NO LINE OF SIGHT, blast divines/AoE still lob. Boots clean, 17/17.
4. **Positional bot** built into BOTH engines (the playtest-gate item):
   Rule A — only VISIBLE targets count; with none, hunt a reachable firing
   tile scored by shot-EV (the real hit_chance prices height bonus, cover
   halving, beacon, point-blank flanks) + 2.0×tile-cover, else close
   distance. Rule B — holding a <50% shot with move+shoot AP, take a perch
   worth ≥0.15×avg-damage more. Rule C — focus lowest-HP visible; single-
   target divines require LOS (no more wasted ults). Zero added RNG draws.

**NEW 2000-run baselines (positional bot, v1 rules) — the numbers to tune from:**

| encounter | blind bot (deprecated) | positional bot | band |
|---|---|---|---|
| skirmish (starter) | .67 | **1.00** | story .70–.85 ↑over |
| vanguard (starter) | .81 | **.96** | story ↑over |
| deacon (starter) | .62 | **.71** | boss .45–.65 ~over |
| foreman (starter) | .47 | **.89** | boss ↑over |
| weaver (starter) | .71 | **.93** | boss ↑over |
| hollow (starter) | .68 | **.92** | boss ↑over |
| finale4 (full) | .53 | **.91** | boss ↑over |
| trail T1 ambush (harness) | .35 | **1.00** | ambush .80–.90 ↑over |
| wilderness T2 ambush (harness) | .00 | **.79** | ambush ~in band |

**How to read this (do not skip):** the positional bot ≈ an UPPER-BOUND
competent player (optimal focus fire, perch-hunting, no mistakes, but no
hunkering/overwatch since those don't exist for it). A real human sits
between the deprecated blind numbers and these. The blind→positional spread
(foreman +42pts, finale +38pts) is the measured value of position under v1 —
Pillar 2 is mechanically real. Most encounters now sit ABOVE their bands for
a positional player: whether that means "retune enemies up" or "bands assumed
a weaker player, adjust bands" is a TIM DECISION for a tuning session with
this instrument + his own playtest. No retuning was done in this pass.

---
# Session #2 — DECISION MEMOS (options prepared for Tim, nothing built)
*Calder, 2026-07-10. Every open question from v1 + the GUTS pass (audit
2026-07-09), 2–3 concrete options each with tradeoffs. Recs marked; picks are
Tim's. Receipts: SYSTEMS_AUDIT_2026-07-09.md clusters cited per item,
COVER_REDTEAM_2026-07-09.md (Njord).*

## 2a. OVERWATCH / reaction fire — v2 #1, Njord's "one thing missing"
Without it, flanking is free movement math and directional cover never faces
risk (red-team §4). Interacts with 2b and 2c below.
- **A. Universal overwatch action (XCOM):** reserve ≥2 AP, snap shot (−15
  aim?) at the first enemy moving through your LOS. + Standard, legible,
  symmetric (enemies get it too — sentries/lawdogs first); makes flanks cost
  blood; the flush-them-with-dynamite combo needs it. − Biggest AI cost
  (enemies must respect threatened lanes or look dumb), needs stance UI +
  telegraphs, slows turns.
- **B. Adjacency attack-of-opportunity only:** free snap shot when an enemy
  LEAVES melee range. + Tiny scope; taxes exactly the point-blank flank v1
  introduced. − Long sightlines stay unguarded; not really "overwatch."
- **C. Covering Fire as a per-kit ABILITY (lawdog/sentry/tinkerer turret
  flavor):** only some units threaten movement. + Characterful, bounded AI,
  no universal economy change. − Flanking stays free vs most comps.
- **Calder rec:** A, scoped to players + sentry-class enemies in the first
  cut. B is a cheap stopgap that can ship inside A later.

## 2b. HUNKER economy — Njord's always-hunker turtle
Today: 1 AP, +0.20 to the block band (cap 0.60), no restrictions — behind
heavy cover, shoot-then-hunker is near-strictly-correct every turn.
- **A. Hunker ENDS the turn:** the classic fix. + One rule kills the dominant
  line; instantly legible. − Binary; removes shoot-then-brace as a texture.
- **B. Hunker requires not having moved:** "braced" flavor. + Softer, keeps
  brace-and-shoot positioning identity. − Doesn't stop the static turtle —
  the exact case Njord flagged (bunker stalemates).
- **C. Hunker tags you PINNED:** keep 1 AP, but while hunkered you can't
  overwatch (2a) and point-blank/flank shots vs you gain +hit. + Counterplay
  instead of prohibition; synergizes with the flank game. − Two moving parts,
  needs 2a to exist for half its teeth.
- **Calder rec:** A for v2 simplicity; revisit C once overwatch lands.

## 2c. DYNAMITE fuse — Tim's own trope, still open
- **A. Fuse-delay:** lands this turn, detonates at the start of your next;
  enemies get one panicked move. + The cowboy-sees-the-lit-stick beat; turns
  dynamite into AREA DENIAL/herding (flush → gun line / overwatch line — the
  fire-support fantasy). − AI must flee blast markers (new behavior), needs a
  lit-fuse telegraph, and herding pays off fully only WITH overwatch (2a).
- **B. Instant boom:** current do_blast behavior, ship as-is. + Zero work,
  classic feel. − Loses the trope AND the herding layer; dynamite stays
  "damage in a circle."
- **C. Split by item:** alchemical ashfall_charge stays INSTANT; stick
  dynamite (bandits + future player item) is FUSE-DELAY. + Teaches both,
  preserves the charge's feel, gives bandits their signature. − Two rules for
  one category; must read clearly in the HUD.
- **Calder rec:** C — the trope lives where the flavor is, and the existing
  consumable doesn't change under players' feet.

## 2d. EDGE-DIRECTIONAL cover — v1 shipped the point-blank proxy
- **A. Full edge model (XCOM):** cover lives on tile EDGES; the bonus applies
  only against shots crossing a covered face; flanking = any uncovered-face
  shot. + Real flanking geometry, the "do it properly" endgame. − The
  costliest option on the board: per-edge grid data for 6 boards, cover calc,
  shield-pip UI, AI move scoring must understand faces, full re-balance.
- **B. Facing-arc approximation:** each cover tile gets ONE protected arc
  (derived from board authoring); cover applies only if the shot crosses it.
  + Most of the flank game at a fraction of A's cost. − Auto-deriving facing
  on scatter-cover desert boards is ambiguous; hand-authoring is real work.
- **C. Keep the v1 proxy (adjacent = flank) + overwatch as the tax:** revisit
  after a human playtest. + Zero cost now; overwatch (2a) already makes the
  walk-around risky. − Flanking stays binary adjacent-or-nothing.
- **Calder rec:** C until Tim's playtest says the proxy feels wrong; if the
  flank game needs to be the star, B before A.

## 2e. DIFFICULT terrain (double-MP tiles)
- **A. Data-only pass:** mark existing rough/brush tiles double move cost on
  the 6 boards (reach() already prices ascent; a tile moveCost is ~10 lines
  in both engines + parity re-run). + Cheap, real "safe path is the slow
  path" economy. − On ONE fixed board per biome the players memorize it fast.
- **B. New terrain type with visuals + procedural boards:** mud/scree/web
  tiles as part of a map-variety push (audit: every mesa fight is literally
  the same map — repeat-board fatigue is the bigger lever). + Fixes two
  things at once; the unwired map_gen.py exists. − A project, not a pass.
- **C. Defer until board variety exists.** + Focus. − P2's movement economy
  stays two-axis (distance + climb) meanwhile.
- **Calder rec:** C now, A folded into whatever board-variety direction Tim
  picks (see GUTS: the map problem outranks it).

## GUTS PASS (calder-031) — the four holes the audit says matter most

## 2f. THE 5 DEAD STATS (nimbleness/cognition/knowledge/mien/spirit)
Cluster 4: hexslinger + tinkerer level-ups are 100% dead (favored pairs are
both dead stats), preacher/lawdog/drifter 50%; design.json PROMISES dodge /
ability accuracy / crafting / intimidation / fear resistance.
- **A. Wire them minimally to what exists** (one derivation line each, no new
  systems): nimbleness → dodge (flat −hit% on you, composes before the 0.60
  cap) · cognition → +aim on ABILITIES only · spirit → divine efficiency
  (empower threshold or divine mult) · knowledge → consumable potency ·
  mien → recruit price / bounty pay (town-side). + Honors the printed
  promises; fixes caster-archetype scaling invisibly broken since the web
  build. − Every mapping is a BALANCE change (parity + baselines re-run);
  the exact mapping list is a design pick, not a given.
- **B. Cut to 4 real stats:** delete the dead five from pregens/creator/
  FAVORED, rebalance. + Honest, small sheet, no fake depth. − Kills the
  Deadlands-breadth flavor and every future skill-check hook; touches
  creator data + any future sheet.
- **C. Re-route FAVORED pairs only** (2-line data fix): every archetype
  levels stats that exist; the five stay dead but progression works. + Ships
  tonight, zero balance risk beyond +stat growth. − The sheet still shows
  numbers that do nothing; the lie stays printed.
- **Calder rec:** C immediately as a stopgap once Tim nods; A as the real
  fix WITH Tim choosing the mappings (the list above is a menu, not a spec).

## 2g. LOOT / DROPS — cluster 3: zero drops anywhere, 8 of 22 items
unobtainable, economy exhausted by mid-Act II
- **A. Tier-unlock the catalog tail:** outfitter/forge stock keyed to town
  tier (T2 adds mid gear, T3 sells hex_focus / steam_cannon /
  blessed_vestments / clockwork_exo). + Pure data change; instant gold sink;
  the items are already statted, gated, and parity-tested. − Which item lands
  at which tier/price IS the economy design (Tim's table to fill); no
  drop-thrill, just shopping. (Note: ashfall_pistol's armor-piercing niche
  needs enemies to HAVE armor first — separate decision.)
- **B. Battle drops:** port the haunts.js/encounter_gen loot tables into a
  post-battle drop roll by encounter tier. + The actual "loot game"; makes
  ambushes/bounties worth fighting past gold-cap. − New system: drop tables,
  result-screen UI, inventory pressure → wants the character/inventory
  screen (2i) to exist.
- **C. Staged both:** A now, B behind the haunts-wiring decision (audit
  cluster 1 flags haunts.js as the cheapest playtime multiplier overall).
- **Calder rec:** C — A is a lunch-break build once Tim fills the tier table.

## 2h. BOSS MECHANICS — cluster 6: five bosses, one enrage template, while
design.json promises boss-summon / boss-turret / boss-possess / boss-clones /
boss-webs (strings mapped by NOTHING in either build, ever)
- **A. Implement the five promised kits minimally** (~15 lines each in
  enemy_to_unit/enemy_phase per the audit): Deacon raises 1 walkin_dead every
  other turn pre-enrage · Foreman goes sentry-mode + deploys a forge_sentry
  once · Hollow Man's hits confuse (1 turn, cooldown) · Coyote's Shadow
  spawns 1-HP decoy clones · Weaver webs tiles (slow/root status; full web
  terrain wants 2e). + Highest depth-per-line on the board; each boss finally
  matches its lore card; parity harness catches drift per boss. − Five
  balance passes, five telegraphs/FX, boss-band re-tune after (they're
  already over-band vs the positional bot).
- **B. One shared SECOND mechanic for all five** (e.g. midfight lieutenant
  call or arena change). + One build, some variety. − Bosses stay reskins,
  just two-beat reskins.
- **C. Defer; spend the effort on board variety** (audit argues repeat-board
  fatigue ≥ boss sameness for the $10 ask).
- **Calder rec:** A, one boss at a time, Deacon first (he's the demo's Act-I
  face) — each behind its own baseline re-run.

## 2i. CHARACTER SHEET / party screen — clusters 4+5: stats, XP, level, and
wounds are INVISIBLE everywhere; bench slots 5-6 strictly negative (never
fight, dilute XP) with no reorder UI
- **A. Town "Posse" tab:** read-only member rows (level, XP bar, 9 stats,
  gear, wounds) inside the existing town UI. + Cheapest real surface; no new
  scene. − Not visible in battle or on the worldmap where the questions
  ("who's hurt? who levels next?") actually arise.
- **B. Pause-menu party sheet, everywhere:** new panel in the pause autoload;
  the natural home for BENCH REORDER (choose your four) later. + The real
  answer; kills the invisible-math problem game-wide; reorder fixes the
  strictly-negative bench. − Largest UI build of the three; pause menu is
  currently just audio/quit.
- **C. Battle hover-card only:** stats on unit hover in fights. + Tiny.
  − Doesn't answer between-fight questions; XP/level stay hidden.
- **Calder rec:** B, shipped WITH bench reorder (the sheet without the fix
  it enables is half the value). Reorder mechanics are mechanical once the
  sheet exists; changing the bench XP-dilution rule itself = Tim's call.

## Flags noticed while working (no action taken)
- **Ability range is ungated in the interactive game:** basic fire enforces
  dist ≤ rng+1 (battle.gd), but targeted ABILITIES fire at any distance —
  the math just piles on −15/tile falloff. Bug or "desperate long shots are
  very western"? Tim's call which way to make it consistent.
- **Sim bot still never hunkers** — fine for offense measurement, but the
  hunker-economy options (2b) can't be sim-compared until the bot learns it.
- **d86802b (forge-imggen img2img) landed mid-session from the imggen lane**
  — no combat overlap, noted for the record.

---
## Session #2 ANNEX — Njord red-team of the memos (2026-07-10 overnight)
Full verdict: **docs/REDTEAM_MEMOS_NJORD_2026-07-10.md** — read it whole; it
has a flip-summary table (Njord counter-recs vs Calder recs on all 9 memos)
and a "what I'd tell Tim in one pass" close. Author≠verifier held: the memos
were red-teamed by a different node than wrote them. Picks remain Tim's —
you now have two argued positions per question instead of one.

**Corrections Calder OWNS (Njord caught real errors in the memo text above):**
1. **2a option B is mis-specified.** Adjacency attack-of-opportunity as
   written fires when an enemy LEAVES melee — but the point-blank flank
   happens on ENTER. As listed, B does NOT tax the v1 flank. If a cheap
   reaction is wanted, the trigger must be enter-adjacent (or leave-cover).
2. **2f option C is NOT "zero balance risk."** Re-routing FAVORED pairs
   means hexslinger/tinkerer start gaining REAL combat stats every level
   where today they gain none — that's a buff, and it needs a baseline
   re-run like everything else. (Low-risk ≠ zero. Mea culpa.)
3. **2g option A is not a "gold sink."** Shop stock is a POWER FAUCET that
   happens to absorb gold; it only sinks if prices hurt and something
   (upkeep/ammo/repair) keeps pulling gold out. Njord: price the tiers
   against the real gold curve + land at least one sink first, or Act II
   gets a power spike on top of already over-band encounters.
4. **2h's "~15 lines each" understated the true cost.** That figure is the
   AUDIT's estimate for the behavior mapping alone (enemy_to_unit/
   enemy_phase); telegraphs, FX, statuses, parity cases, and per-boss
   balance re-runs are the real bill. The option stands; the estimate
   doesn't.

**Njord's baselines frame (endorsed as the sharper read):** treat the
blind→positional DELTAS as the finding (Pillar 2 proof: foreman +42,
finale +38), not the absolute win rates as tuning targets. Saturated rows
(skirmish 1.00, trail-T1 1.00) are ALARMS — the metric is pegged and can't
see buffs there. The positional bot prices offense only (no hunker, no
overwatch, no baiting), so today's numbers are a pre-defense snapshot that
2a/2b/2c will invalidate. Human playtest sets band centers; the sim detects
regressions and soft content.

---
# Session #2 DECISIONS — Tim's picks (2026-07-10, ~00:30 PT, live)
*Tim read the memos + Njord's annex and picked. Recorded with the why.*

- **2b HUNKER → ends the turn** (XCOM-style). One rule kills the
  shoot-then-hunker dominant line. Njord's brace-texture concern noted;
  revisit alongside overwatch.
- **2c DYNAMITE → split by item.** Stick dynamite (bandits now, player item
  later) = FUSE-DELAY: lands lit with a telegraph, detonates at the start of
  the thrower's side's next phase, the other side gets one panicked move —
  area denial/herding. Ashfall charge stays INSTANT (alchemical). The trope
  lives where the flavor is.
- **2f DEAD STATS → re-route + gray out** (stopgap; full wiring is a future
  design session). FAVORED pairs re-point to live stats so every archetype
  levels something real; dead stats stop being displayed as live. OWNED
  CAVEAT (Njord): this buffs casters — baselines re-run after.
  Re-route mapping (Calder interpretation, Tim may veto): hexslinger
  cognition/spirit→deftness/vigor · tinkerer knowledge/cognition→deftness/
  quickness · preacher spirit/vigor→vigor/strength · lawdog vigor/mien→
  vigor/quickness · drifter nimbleness/quickness→quickness/deftness ·
  gunslinger deftness/quickness unchanged.
- **2h BOSS KITS → Deacon first, alone.** boss-summon: raises walkin_dead
  mid-fight pre-enrage (cadence capped), own balance re-run, then reassess.
  Five-kit program explicitly NOT committed (Njord's cost catch stands).
- **2e DIFFICULT TERRAIN → double-MP now, data-only.** Njord's flip
  endorsed by Tim. Implementation interpretation (vetoable): the boards
  have no "rough" class, so SOFT-COVER tiles (brush/cactus/wreckage) cost
  double to ENTER — cover routes become the slow routes, open ground stays
  fast but exposed. Both engines + parity + baselines re-run.
- **2i PARTY UI → XP visibility + bench rule first.** Post-battle XP/level
  breakdown surfaced at battle end; ONLY DEPLOYED riders earn XP (bench
  becomes free storage, no more dilution). Pause-menu sheet + reorder is
  the follow-up build. (Balance note: removes the hidden recruit tax.)
- **2a OVERWATCH → HELD for a dedicated design session.** Load-bearing;
  Calder (universal-capped-symmetric) vs Njord (kit-first) gets argued
  live. Until then the point-blank rule remains the only flank tax.
- **2g LOOT/ECONOMY → HELD for a dedicated session** with the real gold
  curves. Njord's faucet≠sink catch accepted; no catalog opening blind.

---
## Session #2 BUILD RUN — all six picks landed (2026-07-10 night,
## commits d2f2a0f · 02aedd6 · 7887e75 · b26c801 · db9d8bd · 3dff43b)
Every item: parity Δ 0.0 (bit-exact both engines), positioning 17/17,
god_swear 5/5, battle parses + boots clean. Baselines re-run per combat
change (numbers below are sequential — the shared RNG stream ripples ±0.2
between steps; that ripple is mirrored identically in both engines).

| change | deacon | foreman | weaver | hollow | finale4 | vanguard | notes |
|---|---|---|---|---|---|---|---|
| post-red-team base | .714 | .888 | .925 | .920 | .908 | .962 | positional bot |
| + hunker ends turn | .744 | .900 | .933 | .920 | .918 | .965 | bot banks AP as brace |
| + rough terrain | .772 | .964 | .940 | .949 | .911 | .974 | slows the closers |
| + fuse dynamite | .771 | .964 | .938 | .950 | .910 | .988 | bandits dodgeable |
| + Deacon kit (FREE raise) | **.774** | .968 | .935 | .950 | .913 | .988 | identity, ~neutral |

**The instrument earned its keep live:** the Deacon kit as first specced
(raise REPLACES his shot) measured **+7pts EASIER** (.843) — a boss-grade
attack traded for a slow corner-spawn zombie is a self-nerf. Tim picked the
FREE raise on the spot → .774, balance-neutral with the summoner identity
intact. This is the design loop working: spec → measure → fork → pick →
re-measure, inside an hour.

**Standing read for the tuning session (unchanged):** deltas are the
signal; skirmish/T1 rows are saturated alarms; everything sits above band
for a positional player and the gap is GENERAL enemy tuning — one session
with these dials, not per-system nerfs. Skirmish 1.00 in particular means
the default Quick Skirmish has no teeth for a competent player.
Also shipped this run: deployed-only XP + per-rider battle-end breakdown
(2i first cut), FAVORED re-route + LIVE_STATS convention (2f stopgap —
casters finally level).

---
## OVERNIGHT ANNEX — Njord red-team #2 (the SHIPPED rules) + code-verified
## answers (2026-07-10 overnight; full verdict docs/REDTEAM_RULES_NJORD_2026-07-10.md)

Njord exploit-hunted the four shipped rules + deployed-only XP. I verified
every §11 blocker against the actual code. Verdicts with receipts:

1. **Kit-raised dead PAY full kill XP — CONFIRMED (CRITICAL).**
   apply_damage increments kills for any side-e death (combat_core.gd:344,
   no raisedBy exclusion); apply_battle_result pays kills×10. Every Risen
   Dead the Deacon raises is a 10-XP piñata.
2. **Enrage is HP-gated ONLY — CONFIRMED.** check_boss_phase:492 fires
   solely at hp ≤ 50%. A player who never damages the Deacon stays
   pre-enrage forever → **the XP farm is UNBOUNDED as shipped**
   (~5 XP/round gross at the raise cadence, deployed-only XP removes the
   dilution brake, and the new battle-end XP breakdown TEACHES the farm).
   Njord's P0 stands: ship-block class for a demo containing the Deacon.
   Closure options (TIM PICKS, none implemented): kit adds worth 0 XP ·
   per-fight kit-XP budget · enrage turn-timer or anti-ignore (enrage if
   unhurt K turns) · adds excluded from kill count.
3. **Shoot-then-hunker is STILL LEGAL — CONFIRMED.** The 2b intent was
   "kill the dominant line," but ends-turn ≠ mutex: hunker only needs ≥1 AP
   (battle.gd), and maxAp is 3+ for everyone — shoot (2 AP) then hunker
   (ends turn) fits every turn. The dominant line survived the nerf.
   Options (TIM PICKS): hunker requires full AP (no actions spent) · hunker
   forbidden after attacking · accept shoot-then-brace as intended texture.
4. **Thrower death does NOT defuse — CONFIRMED.** tick_charges never
   references the thrower; the stick booms regardless. No kill-to-defuse
   counterplay. (Flag, arguably fine — dead man's dynamite is very western.)
5. **Rough scar after cover break — INTENTIONAL, Calder interpretation,
   vetoable.** Njord notes the inverted incentive: breaking brush can
   worsen YOUR approach. Alternative: rough only while the cover object
   stands.
6. **Bot brace ⊆ player rules — ALIGNED.** The bot's end-of-activation
   brace is the same action a player may take with spare AP; the bot uses
   a strict subset of legal options, so post-hunker baselines don't
   overstate player defense. (Njord's Hole C doesn't bite — but his larger
   point stands: WR alone can't see farms, stalls, or duration; the
   instrument needs XP/duration columns, queued for the dial-map tool.)

Also confirmed from code while verifying: sticks DO crack/delete cover on
detonation (delayed cover-deletion, Njord §3C-4) and charges stack per tile
(damage and −5.5 bot-avoid both stack). His −5.5-is-a-policy-hammer and
rough×fuse (flee across brush can be impossible) findings look right by
inspection and are queued as instrument/AI follow-ups after Tim's picks.

**Morning decision list distilled: (a) close the Deacon farm (pick a
closure), (b) hunker mutex or accept the texture, (c) rough-scar keep or
revert, (d) later: fuse-avoid EV model, spawn-slot variety, XP/duration
instrument columns.**

---
# ☀ MORNING DIGEST — 2026-07-10 (overnight lane, 07:00 PT)

## The night in one paragraph
Everything you picked at 1 AM shipped and held green, then the lane built
the rest of the decided queue: the **posse sheet + ride-order reorder** is
in the pause menu (98023ce — Esc → Posse anywhere: XP bars, wounds, live
stats bright / dormant dimmed, gear, sworn god; top 4 ride), the new rules
got **26 deterministic tests** (643cf73 — fuse, Deacon cadence/cap, rough
MP, brace, level-up re-route proof for all six archetypes), your three
session packs are on disk, Njord red-teamed the shipped rules overnight,
and every finding was **verified against code** before it reached you.
Parity stayed **bit-exact (Δ 0.0)** through all of it — now with rounds +
kills columns in the standard check (9314550) so farms and stalls show up,
not just win rates. 9 commits, all pushed.

## YOUR PICKS, priority order (nothing was implemented — all yours)
1. **P0 — close the Deacon XP farm.** CONFIRMED unbounded: raised adds pay
   full kill XP (combat_core.gd:344) and enrage triggers ONLY at ≤50% HP
   (check_boss_phase:492) — never poke the boss, farm ~5 XP/round forever;
   deployed-only XP removed the dilution brake and the new XP breakdown
   TEACHES it. Options: **kit adds worth 0 XP** · **per-fight kit-XP
   budget** · **enrage turn-timer** · **anti-ignore enrage** (enrage if
   unhurt K turns). Ship-block class for any demo containing the Deacon.
2. **Hunker mutex.** Shoot-then-hunker SURVIVED the ends-turn nerf (hunker
   needs 1 AP; everyone has 3+): the 2b dominant line still runs. Options:
   **hunker requires full AP** · **no hunker after attacking** · **accept
   it as intended texture**.
3. **Rough-scar veto.** My interpretation: brush stays slow after its cover
   breaks. Njord notes it inverts an incentive (breaking cover can worsen
   YOUR approach). Options: **keep the scar** · **rough only while the
   cover object stands**.
4. **Sessions ready when you are:** overwatch (docs/OVERWATCH_SESSION_
   BRIEF.md — the one real fight, me vs Njord, matrix + parameter sheet) ·
   loot/economy (docs/ECONOMY_DATASHEET.md — 2010g catalog vs one
   repeatable 100-180g faucet; sinks die mid-Act-II, now with numbers) ·
   boss-band tuning (docs/TUNING_DIALS_2026-07-10.md — 162-cell sweep;
   headline: aim is a weak dial vs positional play, and no boss row lands
   in band before ×1.4 on any single global dial — comps and rules are the
   real levers).

## Board state (forge)
calder-032 (P0 farm) · calder-033 (hunker mutex) — TIM-GATED picks filed;
calder-034 (overwatch build, unblocks the hour you pick); calder-035
(instrument columns) filed AND LANDED overnight (9314550). calder-027
verify-blocker flagged to the SiteLens lane, untouched from here.

---
# MORNING PICKS — Tim, 2026-07-10 morning (in-chat, decided)
1. **P0 farm closure → KIT ADDS PAY 0 XP.** Airtight one-line-class fix:
   raised dead grant no kill XP; clearing them is its own reward (safety).
   Kill COUNT stays truthful everywhere (banner, instrument conveyor
   column) — only the XP payout excludes raised units (new xpKills
   counter, both engines; battle-end XP now pays on xpKills).
2. **Hunker mutex → NO HUNKER AFTER ATTACKING.** Kills exactly the
   shoot-then-brace dominant line; move-then-brace (hold the line) stays.
   Applies to the interactive button AND the sim bot's end-of-activation
   brace (which was itself the shoot-then-brace line) — defense baselines
   re-measured after.
3. **Rough scar → KEPT.** Wreckage stays slow after the cover object
   breaks; the inverted incentive (blasting a path can slow your own
   approach) is ruled a tactical tradeoff, not a bug. Playtest may reopen.
