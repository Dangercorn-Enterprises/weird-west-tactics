# REDTEAM — Session #2 Decision Memos + Positional Baselines
**Njord · 2026-07-10 · Dustfall lane (calder-031) · advisory only**

Scope: DESIGN_LOG_20260710.md Session #2 memos 2a–2i + positional-bot baselines table/read.
Prior COVER_REDTEAM path cited in log was not on disk; this stands alone.
Format: missing options · bad tradeoff claims · flips · baselines frame. No build advice beyond choice quality.

---

## 0. BASELINES FRAME — is "positional = upper bound" safe for tuning?

**Short answer: NO. Useful instrument, wrong frame for tuning targets.**

What the table actually is:
- A specific offense policy (visible-only targets, perch EV, focus lowest-HP, LOS-gated divines) vs LOS-aware enemy AI.
- Not "optimal play." Missing: hunker, overwatch, ability sequencing depth, consumable/favor timing, baiting, retreat, multi-unit herding, risk-positive variance plays.
- Log already admits sim never hunkers — so it cannot price 2b, and prices pure aggression only.

Traps if you treat it as upper bound to tune into story/boss bands:

1. **Ceiling saturation.** Skirmish 1.00, trail T1 ambush 1.00 — metric is dead. You cannot see buffs, only nerfs that drop off the floor. Soft content is unmeasured.
2. **Upper-bound bias → retune enemies up.** Framing "competent ceiling" pushes Tim to raise threat until pos sits in-band. Mid human (between blind and pos) then falls under-band. Bands written for a weaker player + enemies tuned for a god-bot = trap.
3. **Instrument will lie after 2a/2b/2c.** OW + hunker-ends-turn + fuse herding change the policy class. Today's 1.00/0.91 is not a stable ceiling; it's a pre-defense snapshot. Tuning HP/damage to today's pos locks in a wrong equilibrium.
4. **Asymmetric policies ≠ skill ceiling.** Bot-vs-bot / player-pos vs enemy-AI is a matchup score, not "how good can a human be." Party stats, encounter scripts, and AI holes are confounded with "position skill."
5. **Blind→pos deltas are the real gold.** Foreman +42, finale +38 = Pillar 2 proof. That delta is the diagnostic. Absolute WR is not a tuning target until Tim's hands set the feel.

**Right frame:**
- Positional WR = regression / pillar-value meter + soft-encounter detector (1.00 = no teeth even for the script).
- Human playtest (Tim) sets band centers.
- Do not retune encounter math off pos alone while defense tools and drops/stats are still landing.

**Read sanity:** table construction is fine; "do not retune off blind bot" was correct; replacing it with "tune from positional upper bound" overcorrects. Human between blind and pos is the only honest sentence in that paragraph — keep that, drop "upper-bound" language.

---

## 2a. OVERWATCH / reaction fire

### Missing options (obvious, not on the list)
- **D. Leave-cover / enter-open reaction only** — fire when a unit breaks cover or ends exposed in LOS. Smaller AI surface than full lane OW; taxes the actual flank path.
- **E. Hard-capped reaction (1 shot/unit/turn, −aim, move-trigger only)** — XCOM without multi-reaction turn sludge; should be a modifier on A, not left implicit.
- **F. Brace-overwatch hybrid:** unit that did not move gets a free reaction arc (couples 2a+2b; western "hold the line").
- **G. Suppression not damage:** movers through LOS take pin/−hit, not a kill roll — lower AI lethality variance, still taxes flanks.

### Tradeoffs wrong or overstated
- **B "taxes exactly the point-blank flank v1 introduced"** — WRONG. AoO on *leaving* melee misses the approach that *enters* adjacent for the flank. Classic wrong trigger. Enter-threatened or leave-cover is the tax; leave-melee is not.
- **A "biggest AI cost"** — breadth cost yes; architecture novelty overstated vs C (same threatened-lane problem, fewer units).
- **A "slows turns"** — true of uncapped multi-OW; false of E-capped design. List A as if the slow is inherent.
- **Calder "players + sentry enemies only"** — asymmetric OW undercuts "flanks cost blood." Player flanks stay free vs non-sentry majority; player power rises on already over-band fights (skirmish/finale pos .91–1.00). Symmetric rules or gated both sides — not universal for one team.

### Flip
**FLIP Calder A-first → C (kit ability) first, symmetric player kits + enemy sentries; promote to universal A only with E-caps and a planned baseline re-run.**
If a one-week flank tax is mandatory and 2a full slips: **fixed B as enter-adjacent snap**, not leave-melee.
Do not ship player-universal OW into 1.00 skirmish without a retune plan.

---

## 2b. HUNKER economy

### Missing
- **D. Hunker costs 2 AP** (or "all remaining AP if ≥2") — softens shoot-hunker without binary end-turn.
- **E. Hunker only in cover + once-per-N-turns / grit spend** — kills open-tile nonsense and pure spam.
- **F. Soft mutex:** cannot hunker if you already attacked (brace *or* shoot) — keeps texture, kills the dominant line, without full end-turn.

### Tradeoffs wrong or overstated
- **C "needs 2a for half its teeth"** — OVERSTATED. "+hit to point-blank/flank vs hunkered" is full teeth under *current* v1 flank proxy. Only the "can't OW" clause needs 2a.
- **A "one rule kills the dominant line"** — true, but tradeoff undersells the new binary: pure turtle wait vs pure aggression. Without OW in the same cut, western brace-and-hold dies.
- **B diagnosis** (doesn't stop static turtle) — CORRECT; keep.

### Flip
**FLIP Calder A → C now (or D/F if Tim wants simpler than pinned).** Ship A only same patch as 2a.
Reason: v1 already has flank/point-blank; C uses it. A-before-OW removes defensive texture the fantasy wants. Note: **sim cannot compare 2b options until bot hunkers** — any pick is playtest-gated, not harness-gated.

---

## 2c. DYNAMITE fuse

### Missing
- **D. Cook choice:** player chooses short fuse (near-instant, self-risk) vs long fuse (herd) on throw.
- **E. Tile object:** stick sits lit; kick/throw-back possible — peak western, peak cost; list as stretch.
- **F. Detonate end of enemy phase** (not only start of your next) — shorter herd window, less multi-turn bookkeeping.

### Tradeoffs wrong or overstated
- **A "herding pays off fully only WITH overwatch"** — OVERSTATED. Flush from heavy cover into gun-line LOS is value on *your next activation* without OW. OW amplifies; it does not gate the trope.
- **C two-rules cost** — fair; understates HUD teaching load in a build already teaching LOS/bands/beacon.
- **B "classic feel"** — fine; "loses herding layer" is true, "loses western" is partial (instant boom is also western).

### Flip
**No hard flip.** Calder C is sound (trope on stick, ashfall stays instant).
Soft preference if Tim wants one rule: **A over C**. Reject the claim that 2a is a hard dependency for fuse-delay value.

---

## 2d. EDGE-DIRECTIONAL cover

### Missing
- **D. 4-bit cardinal face flags per tile** (N/E/S/W) — not full edge mesh, not one arc; middle cost.
- **E. Team flank (Fire Emblem):** cover ignored if 2+ allies threaten from different ordinals — zero edge authoring.
- **F. Angle test:** cover applies if shot within ±90° of authored cover normal — continuous, less data than A.

### Tradeoffs wrong or overstated
- **C "OW already makes walk-around risky"** — OVERSTATED while 2a unbuilt. C today is "keep binary adjacent flank," not "OW taxes the walk."
- **A costliest** — believable; not challenged.
- **B authoring ambiguity on desert scatter** — fair.

### Flip
**Conditional.** Calder C is fine *if* 2a ships next. **If 2a slips: flip C → E or F** so flank geometry gains teeth without the full edge project. Do not sit on adjacent-proxy + no OW + no edge — that's the free-flank bug the red-team already named.

---

## 2e. DIFFICULT terrain

### Missing
- **D. Setpiece-only double-MP** (1–2 boards: wash, scree approach) — teaches economy without six-board project.
- **E. Cover-adjacent rubble tax only** — path to safety costs MP; no full terrain atlas.

### Tradeoffs wrong or overstated
- **A "players memorize it fast" ⇒ weak value** — OVERSTATED/wrong implication. Tactics games run on memorized boards; double-MP still forces path tradeoffs *every fight*. Memorization ≠ dead system. Map-repeat fatigue is a *different* problem (board variety), wrongly used to kill a cheap movement axis.
- **C "focus"** — real, but ranks a ~10-line pass below "wait for map project" without need.

### Flip
**FLIP Calder C → A (data-only on existing boards), with D as optional scope cut.**
Board variety remains the bigger feel lever; that does not justify refusing the movement-economy axis for free. Folding A into a future variety project is how cheap P2 pieces die on the vine.

---

## 2f. FIVE DEAD STATS

### Missing
- **D. Hide/gray unwired stats in UI now** — sheet honesty without combat math.
- **E. Level picks named perks instead of dead numbers** (one benefit row) — depth without 9 live derivations.
- **F. Wire combat three first (nimble/cogn/spirit), park mien/knowledge on town/loot only** — staged A.

### Tradeoffs wrong or overstated
- **C "zero balance risk beyond +stat growth"** — WRONG. Re-routing FAVORED onto live stats means casters who previously "leveled nothing" now gain real combat stats. That is a balance change. Lower risk than A ≠ zero.
- **A dodge before 0.60 cap** — underspecified; nimble+hunker+heavy can stack into unhittable without composition rules. Mapping list is a menu — agree — but dodge order-of-ops is a landmine, not a free line.
- **B "kills every future skill-check hook"** — OVERSTATED. Hooks can return; you're killing sheet breadth now, not the concept forever.

### Flip
**Sequence stands (C stopgap → A real) but amend C:** not zero-risk; re-run baselines after FAVORED reroute.
**Add D with C** — stop printing lies.
Do not ship A dodge without a stack cap vs cover/hunker.

---

## 2g. LOOT / DROPS

### Missing
- **D. Boss first-clear uniques only** — progression spike without full drop economy.
- **E. Sinks first:** repair/ammo/shrine/upkeep — "exhausted mid-Act II" can be missing sinks *or* missing goods; A alone is power injection, not a sink.
- **F. Crafting loop** tied to knowledge (cross 2f) as gold/item sink.

### Tradeoffs wrong or overstated
- **A "instant gold sink"** — WRONG as stated. Tier-unlocked shop stock is a **gold faucet of power** when purchased; it only "sinks" gold if prices hurt and power is gated. With pos already over-band, dumping catalog mid-gear raises ceiling further.
- **B needs inventory UI** — fair.
- **C staged** — direction ok, diagnosis thin.

### Flip
**Partial FLIP of "A is lunch-break, just do it":** do not open mid/high catalog until (1) Tim prices tiers against current gold curves and (2) at least one sink exists. Prefer **D (boss uniques) + E (sinks) before full A tail**, then B with 2i.
Otherwise Act II becomes shop-stat-check on top of 1.00 positional skirmish.

---

## 2h. BOSS MECHANICS

### Missing
- **D. Scripted phase beats without new unit types** (cover blowdown, arena shift, enrage changes rules) — cheaper than summon/turret kits.
- **E. Differentiate enrage triggers/effects only** (shared template, five flavors) — between B and A.
- **F. Hard scope: Deacon + Foreman only (demo faces); others wait** — Calder's "one at a time" should be an option with a stop condition, not an implied five-kit march.

### Tradeoffs wrong or overstated
- **A "~15 lines each"** — DANGEROUSLY UNDERSTATED. Summon/turret/confuse/clone/web each imply AI rules, telegraphs, FX, status, parity cases, baseline re-runs. Depth-per-line claim collapses if line count is fantasy.
- **A "highest depth-per-line on the board"** — marketing, not estimate. Five balance passes after already over-band bosses is the real cost line — that part is honest; the 15-lines bit is not.
- **C board variety ≥ boss sameness for $10** — plausible for trail fatigue; weak if demo sells named boss fights. Not a free defer.

### Flip
**Keep Deacon-first, REJECT five-kit commitment and the 15-line estimate.**
**FLIP full A → F: Deacon then Foreman under A-minimal; E/D for Hollow/Coyote/Weaver until boards/OW settle.**
Adding walkin_dead spam to Deacon vs pos .71 will swing WR hard — good — but only with explicit post-kit baseline gate (Calder says this; enforce it, don't handwave 15 lines).

---

## 2i. CHARACTER SHEET / party screen

### Missing
- **D. Persistent party strip** (HP/wounds/level pips) on battle + worldmap — answers acute questions without pause rebuild.
- **E. Post-battle XP/level breakdown first** — surface at the moment XP lands.
- **F. Rule fix: bench does not dilute XP / only deployed earn** — kills strictly-negative slots without UI.

### Tradeoffs wrong or overstated
- **A location weakness** — fair.
- **B as largest UI** — fair.
- **C insufficient alone** — fair.
- **Calder "sheet without reorder is half value"** — slightly OVERSTATED. Invisible XP/wounds are the acute wound; reorder is the bench wound. Both matter; sheet alone is more than half if F also lands.

### Flip
**Soft FLIP on priority, not destination:** ship **E + F immediately**; **B + reorder as the real build**. Do not block honesty of XP on pause-menu architecture. Calder end-state B is correct.

---

## FLIP SUMMARY (Calder rec → Njord)

| Memo | Calder | Njord | Why |
|------|--------|-------|-----|
| 2a | A scoped players+sentry | **C symmetric first; A only with reaction caps + retune plan** | Asymmetric OW buffs over-band player; B trigger is wrong |
| 2b | A end-turn | **C (or D/F) now; A only with 2a** | Teeth exist via flank; A-before-OW strips brace fantasy |
| 2c | C split | **Hold C** (soft: A if one-rule) | 2a dependency overstated |
| 2d | C wait playtest | **Hold if 2a ships; else E/F** | Proxy+no OW = free flank remains |
| 2e | C defer | **A data-only (or D setpiece)** | Memorization claim misused; cheap P2 axis |
| 2f | C then A | **C+D then staged A; C is not zero-risk** | FAVORED reroute buffs casters; stop printed lies |
| 2g | C (A then B) | **E sinks + D uniques before fat A catalog** | Shop stock ≠ sink; power spike on soft content |
| 2h | A all five, Deacon first | **Deacon+Foreman only; reject "15 lines"** | Cost fantasy; over-band bosses need gates |
| 2i | B+reorder | **E+F now, B+reorder next** | Acute info vs architecture |

---

## Cross-memo dependency lies

1. **2a is treated as load-bearing for 2b-C, 2c-A, 2d-C.** Only 2d-C truly needs a flank tax substitute; 2b-C and 2c-A work without OW. Stop serializing the whole v2 stack behind universal overwatch.
2. **2e deferred "because maps"** confuses board identity with movement pricing.
3. **2g-A as sink** will fight 2h retunes and positional over-band if catalog power lands first.
4. **Flags:** ability range ungated vs basic fire gated — pick one (western long-shot with falloff is coherent; silent inconsistency is not). Bot-never-hunkers means **2b is playtest-only** until policy learns brace.

---

## What I would tell Tim in one pass

- Trust blind→pos *deltas* as proof of Pillar 2. Do not trust absolute pos WR as a difficulty target while defense tools, stats, and loot are still moving. 1.00 rows are alarms, not trophies.
- Build flank tax (2a-C or enter-adjacent reaction) and hunker teeth (2b-C/D/F) before universal XCOM OW.
- Fuse-delay does not wait on OW.
- Double-MP is a cheap axis — take it; don't hostage it to mapgen.
- Stop printing dead stats; FAVORED reroute is a real buff; measure it.
- Do not open the item tail as a "sink" without prices and upkeep; boss uniques first.
- Deacon kit yes; five promised kits as a single program no — estimate is a lie.
- XP visibility and bench XP rule before pretty pause sheet.

— Njord
