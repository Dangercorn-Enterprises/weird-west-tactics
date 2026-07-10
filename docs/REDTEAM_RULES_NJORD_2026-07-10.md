# REDTEAM — Session #2 SHIPPED RULES (exploit hunt)
**Njord · 2026-07-10 · commission #2 (calder-031 / Dustfall) · advisory only**

Scope: four rules landed in BUILD RUN (commits d2f2a0f…3dff43b) + deployed-only XP.
Sources: DESIGN_LOG_20260710.md Session #2 DECISIONS + BUILD RUN; commission brief.
No repo touch. No code execution. Numbers from stated rules only.

---

## 0. VERDICT UP FRONT

| Rule | Dominant-line risk | Severity |
|---|---|---|
| Hunker ends turn | Shoot-then-hunker may still be legal if AP≥3; pure heavy-cover turtle is the new dominant without OW/explosives | **HIGH** (verify AP) / MED once verified |
| Fuse-delay dynamite | Chokepoint herding strong; AI −5.5 avoid is overweighted and abusable | **MED–HIGH** |
| Rough (soft-cover double enter) | Body-block + permanent slow scars after light cover dies | **MED** |
| Deacon free raise | **XP farm is real under stated rules if enrage is HP-gated and kit adds grant kill XP** | **CRITICAL** |
| Cross-rule | Heavy hunker + free raises + no OW + deployed-only XP = safe pre-enrage grind | **CRITICAL** |

Instrument (pos bot WR) does **not** see the farm, the turtle, or human herding. Deacon .774 ~neutral is irrelevant to the XP hole.

---

## 1. PRIORITY: Deacon free raises × deployed-only XP = unbounded farm?

### Stated facts used
- Pre-enrage: FREE raise 1 `walkin_dead` every other Deacon activation.
- Cap: max 2 kit adds alive; raise skipped while at cap.
- Spawn: first free spawn slot.
- Enrage: unchanged (trigger not restated in BUILD RUN).
- XP: kill awards **10 XP** (commission); **only deployed** riders earn (bench is free storage, no dilution).
- Deacon still acts on raise turns (FREE = does not replace shot — BUILD RUN: replace-shot fork was rejected as self-nerf).

### Throughput (hard cap)

Raise rate, not kill speed, gates the farm.

```
raise_attempt on activations where (activation_index % 2 == cadence_phase)
success iff kit_adds_alive < 2
```

**Sustained max kills** if player clears ASAP (always ≤1 alive before next raise):

| Deacon activations T | Max kit raises ≈ | Max kit kills | Gross XP (10/kill) |
|---|---|---|---|
| 2 | 1 | 1 | 10 |
| 10 | 5 | 5 | 50 |
| 20 | 10 | 10 | 100 |
| 40 | 20 | 20 | 200 |
| T even | T/2 | T/2 | **5·T** |

**Rate:** **0.5 kills / Deacon activation ≈ 5 XP / activation** gross into the deployed pool.

If one full round = 1 Deacon activation (boss still up, adds dying same round):
- **≈ 5 XP per round** total from kit adds alone.
- Cap 2 does **not** raise the ceiling; it only **punishes slow clear** (failed raises while 2 live). Optimal farm is kill-on-spawn, not stockpile.

Letting 2 live then double-tapping still yields ≤0.5 kills/activation long-run. No burst exploit on the raise timer.

### Is it unbounded?

**YES, if all of:**
1. Kit adds grant the normal kill XP (10) — **not denied in any shipped text** → default YES.
2. Pre-enrage raises run until enrage — stated.
3. Enrage does **not** fire on wall-clock / turn count alone while Deacon is undamaged — **unknown; enrage "unchanged" without trigger printed**.
4. Battle does not auto-end while Deacon lives.
5. Player can survive Deacon DPS + add DPS indefinitely (see §1.3).

**BOUNDED, if:**
- Enrage is turn-timer / phase-count → farm ≤ 5·T_enrage XP.
- Enrage is HP% but AI/script forces approach / cover break / enrage assist.
- Kit adds are flagged non-XP / half-XP / boss-only credit (not in log → **do not assume**).
- Victory condition or morale ends fight without boss kill (not stated).

### Deployed-only XP multiplies the abuse

Old world: bench diluted XP → farm partially wasted on ghosts.
New world: **100% of kill XP hits the 4 deployed**. Bench is pure storage.

Effects:
- Farm XP density **up** (no 5–6 way split).
- Incentive: park best 4, grind Deacon courtyard, leave bench cold — then (when reorder ships) rotate. Even without reorder, the active four snowball.
- "Removes hidden recruit tax" (log) is true for honest play; for farm it **removes the only soft brake** on per-head XP.

**Distribution ambiguity (does not save you):** whether 10 XP is party pool split vs killer-only changes *who* spikes, not *whether* total power enters the save. Split 4 ways → 1.25 XP/rider/activation sustained; killer-only → one god unit. Both are farms.

### Safe-farm package (cross-rule)

If Deacon lacks reliable explosives / cover-delete and heavy cover stays bullet-immune:

1. Plant 4 deployed on **heavy** with LOS to spawn slots / approach tiles.
2. Plink each raise on spawn (or on enter open).
3. **Hunker** when shot pressure spikes (ends turn — pure brace turns).
4. Never (or minimally) damage Deacon → stay pre-enrage if enrage is HP-gated.
5. Rough tiles between spawns and your line **slow adds** (double enter on soft-cover paths) → free kiting margin.
6. Fuse sticks from any bandit trash: step out of Chebyshev-1, or use −5.5-quality flee if you are the bot; human walks one tile.

**Result:** low-risk, high-repeat kill feed. Pos bot WR .774 does not simulate "ignore boss, farm adds."

### Quantified farm rates (use these)

Assume: 1 Deacon activation / round, raise on every other activation, instant clear, 10 XP/kill, fight length R rounds pre-enrage.

| R (rounds) | Kit kills | Gross XP | Per deployed if split 4 ways |
|---|---|---|---|
| 10 | 5 | 50 | 12.5 |
| 20 | 10 | 100 | 25 |
| 30 | 15 | 150 | 37.5 |
| 60 | 30 | 300 | 75 |

If enrage at round 12 HP-ignoreable: **~60 XP** free before phase change.
If no enrage without HP poke and player never pokes: **unbounded** at **5 XP/round** gross.

**Compare:** one clean boss clear that would have paid a single encounter XP packet is dominated by any farm longer than that packet/5 rounds. Without printed encounter XP totals, treat **any multi-minute stall as a progression break**.

### Mitigations that actually close it (advisory, not build)

Must-fix class (any one hard close; combine preferred):
1. **Kit adds grant 0 XP** (or 1 token XP) — cleanest.
2. **Raise XP budget:** max N kit-kill XP per fight (e.g. first 2 raises only).
3. **Enrage on turn T or on first raise** — time-bounds pre-enrage.
4. **Deacon scales / stops free raise if no player damage for K turns** (anti-ignore).
5. **Adds share boss XP table / don't count as kills** for progression.
6. Soft: raise replaces a shot again (reverts identity; already measured worse WR — use only with other buffs).

**Do not** rely on "player won't notice." Deployed-only XP + post-battle breakdown **teaches** the farm.

**STATUS: CRITICAL — real under stated rules pending enrage-trigger confirmation. Treat as ship-block for demo if enrage is HP-only.**

---

## 2. HUNKER ENDS TURN

### Spec
- Player: hunker ends the turn (+0.20 block band, cap 0.60).
- Sim bot: banks leftover AP as brace.
- Intent: kill shoot-then-hunker behind heavy.

### Hole A — AP arithmetic (verify or fail)

If unit AP pool is **3** and costs are shoot **2** + hunker **1**, then order:

`shoot → hunker (ends turn)`

is **still legal**. "Ends the turn" only forbids actions *after* hunker. It does **not** mutex attack.

The memo called this "one rule kills the dominant line." That is only true if:
- AP < shoot+hunker, OR
- hunker forbidden after attack / costs all remaining AP with attack mutex, OR
- hunker is full-turn exclusive by implementation.

**BUILD RUN does not print the mutex.** Bot "banks leftover AP as brace" after policy actions **sounds like shoot-then-brace restored for the instrument**.

**FINDING:** Until AP table + action mutex are explicit, assume **shoot-then-hunker SURVIVES** for any unit with AP≥3. Severity collapses to "texture loss only" if mutex exists; stays HIGH if not.

### Hole B — pure turtle is the new dominant (no OW)

Even if shoot-then-hunker dies:
- Move to **heavy** (bullet-immune).
- Hunker every turn.
- No overwatch (2a HELD).
- Point-blank flank is the only tax — requires enemy walk-up.

Enemy without explosives / fuse / ignore-cover **cannot break** the brick. Stalemate or AI suicide into cover band.

Who has explosives on Act I boards?
- Dynamite bandits: fuse sticks (herd/damage).
- Deacon kit: raises, not printed as blaster.
- Many gun-line enemies: brick forever.

**FINDING:** Hunker-ends-turn without OW or explosive density **converts** "always brace after shoot" into "never leave heavy." Pillar 2 wants maneuver; this rewards parking.

### Hole C — bot brace vs human rules asymmetry

If bot auto-braces leftover AP and human must spend an action that ends turn:
- Instrument WR **overstates** defense for the scripted side that banks brace "for free" in the policy tail.
- Baselines after "+ hunker ends turn" ticked **up** (deacon .714→.744 etc.) — consistent with free-ish brace, not with humans losing shoot-brace texture.

**FINDING:** Do not tune difficulty off post-hunker baselines until human and bot share the same brace cost.

### Hole D — heavy stalemate loops

Heavy + hunker + banded cover + no degradation from small arms = **infinite stall** available to either side that can sit on heavy first.

Player stall × Deacon farm (§1) = progression exploit.
Enemy stall = boring fights / softlocks if victory needs aggression.

### Interactions
- **× rough:** approach to heavy costs double through soft-cover belts → harder to punish turtle with melee.
- **× fuse:** only reliable anti-turtle flush if bandits present and AI/player throws correctly; Deacon-alone fights lack it.
- **× free raises:** turtle while deleting adds.

**STATUS: HIGH until AP mutex confirmed; MED as pure-turtle meta if mutex exists. Stalemate class open.**

---

## 3. STICK DYNAMITE FUSE-DELAY

### Spec
- Stick (bandit now; player item later): lands lit, detonates start of thrower's next phase.
- Blast: Chebyshev ≤1 (3×3).
- Ashfall stays instant.
- Bot avoids radii at **−5.5 per charge**.

### Intended good
Area denial / herd flush from cover. Western beat. Works without OW (flush into next-turn gunline still pays). Prior memo was right; 2a dependency overstated.

### Exploit A — chokepoint herding

Place stick so the only Chebyshev-safe tiles are:
- open kill lane in your LOS, or
- tile adjacent for point-blank flank next activation, or
- off-map / blocked / rough-taxed dead end.

Without OW, value is delayed one phase — still strong on narrow mesa boards. Human learns one corridor setup; repeats every bandit fight.

**AI thrower:** same geometry against the player. If bandit AI targets "cluster EV" and ignores escape graph, random cruelty; if it path-herds, brutal.

### Exploit B — −5.5 avoid is a policy hammer

−5.5 per charge on tile score is enormous vs typical shot-EV fractions. Effects:
1. **Multi-stick freeze:** 2 lit charges paint wide red zones; bot abandons perch/objective to leave all radii.
2. **Herd into fire without damage:** force bot off heavy into open using threat alone; detonation is optional.
3. **Self-denial:** bandit side throws near own melee path; ally AI refuses to contest.
4. **Wrong tanking:** eating 3×3 blast can be +EV vs walking into 2 overwatch-quality shots or leaving mission-critical cover — fixed −5.5 does not know that.

**FINDING:** −5.5 is a dominant-AI knob. Expect pathing cheese videos: "drop stick, watch boss walk into gunline."

### Exploit C — fuse timing / death / phase edge cases (spec gaps)

Unresolved in log → bug surface:
1. Thrower dies before detonation: stick fizzles or still boom? **Kill-to-defuse** if fizzle; no counter if boom.
2. "Thrower's next phase" vs "thrower's side's next phase" (DECISIONS text uses side). Side phase = longer fuse bookkeeping; unit phase = die-mid-round edge cases.
3. Can second stick stack on same tile? Damage stack? Avoid score stack (−11)?
4. Does blast crack heavy / delete light (explosives rules say yes)? Stick becomes **cover deletion on delay** — stronger than damage.
5. Scatter/lob not in this cut — lands "lit" precise for bandits? If precise, herding is deterministic abuse; if scatter, less.

### Exploit D — rough × fuse

Flee uses MP. Soft-cover enter costs **double**. Chebyshev-1 escape that crosses brush may be **impossible** on low MP / after prior move.

**FINDING:** Fuse + rough makes "panicked move" a lie on brush boards. Stick on the far side of cactus belt = guaranteed hits vs units that already spent MP.

### Exploit E — player future item

When stick is player-usable: same herding without OW still strong; with later OW = flush→react delete. Design wants that fantasy — flag only that **demo bandits already teach the geometry** against the player first.

### Degenerate lines
- Never stand in any painted radius even to finish boss (bot).
- Infinite reset: throw at feet of heavy turtle to force leave (only counter to §2 brick if explosives land).
- Camp just outside r=1, shoot thrower, ignore stick.

**STATUS: MED–HIGH. Herding is feature-shaped; −5.5 weight + rough interaction are the actual bugs. Spec gaps on death/phase are landmines.**

---

## 4. ROUGH TERRAIN (soft-cover double enter, persists after break)

### Spec
- Soft-cover tiles (brush/cactus/wreckage): **double MP to ENTER**.
- Cost remains after cover object breaks (slow scar).
- Open ground fast/exposed.

### Good
Safe path = slow path. Closer-class enemies paid in baselines (foreman jump). Cheap P2 axis — prior flip still correct.

### Exploit A — body-block slow belts

Unit collision + double-enter tiles:
- Stand on the only cheap bypass; force AI through 2× brush or long wrap.
- Two deployed can seal a soft-cover ravine; boss adds spawn into tax zone (§1 farm assist).
- After light cover breaks, scar remains → **permanent throttle** on that approach for the rest of the fight.

**FINDING:** Destroying light cover is not fully rewarded for the attacker if the defender wanted the slow scar more than the bonus. Attackers who break brush to "open a path" may **worsen** their own approach. Invert incentive.

### Exploit B — pathing cheese (human)

1. Hold open ground with range; force enemy AI to path soft-cover because of LOS/cover scoring.
2. Snipe while they pay 2 MP / tile.
3. Reposition along open ring; never enter rough yourself.

Pos bot already perch-hunts; rough makes **refusing soft-cover approaches** more correct → more open-beacon fights, less cover dance.

### Exploit C — AI stuck / wasted MP

If pathfinder undercounts enter cost (parity risk) → unreachable tiles look reachable (softlock / wasted turn).
If overcounts → AI refuses correct aggressive lines.

Not proven without code; flag as **parity-sensitive**. BUILD RUN claims Δ0.0 bit-exact — assume cost is mirrored; still watch human path UI vs actual.

### Exploit D — raise spawns × rough

"First free spawn slot" + rough-adjacent spawns = free slows on kit adds. Amplifies farm safety. If all free slots sit behind brush belts, Deacon kit is self-throttled (may explain ~neutral WR despite free actions).

### Exploit E — hunker line behind rough moat

Heavy tile + adjacent soft-cover ring = castle moat. Melee cannot cheaply enter; guns face heavy band; fuse must land past moat or on you.

**STATUS: MED. Working as designed for economy; body-block + post-break scars + farm synergy are the abuses. Consider: rough clears when cover deleted, or rough only while cover alive.**

---

## 5. DEACON KIT (non-XP issues)

Beyond the farm:

### A — free raise + full shot = hidden DPS budget
Replace-shot measured easier; free raise measured neutral. Neutral WR means **summoner identity added without cost** on the instrument. Human-facing: more bodies, more actions, more target clutter, more XP feed. "Identity, ~neutral" understates player-facing chaos and progression risk.

### B — max 2 cap is not a difficulty cap
It is a **farm smoothness** feature: steady 0.5 kill/activation conveyor. A higher cap would be spikier and less farmable; cap 2 is the smooth grind belt.

### C — first free spawn slot
Deterministic spawn = deterministic camp angles. Players learn slot order once; set up LOS before first raise. Randomize or boss-adjacent forced spawn if camp becomes dominant.

### D — enrage unchanged
Whatever the old enrage was, it was balanced **without** free pre-enrage adds. Adds change clock, damage, and focus fire. "Unchanged enrage" on a changed pre-phase is a balance bug even when WR is flat — WR is win/loss, not duration/XP/resources.

### E — walkin_dead threat not priced in farm section
If adds hit hard, farm costs heals/wounds. If adds are trash, farm is free. Log does not print add stats; **trash adds + free raise = pure XP faucet**.

**STATUS: CRITICAL for XP; MED for fight feel/spawn camping.**

---

## 6. CROSS-RULE INTERACTION MATRIX

| Pair | Interaction | Abuse? |
|---|---|---|
| Hunker × Heavy | Brick that small arms cannot clear | YES — stalemate |
| Hunker × Deacon raises | Brace while deleting adds | YES — safe farm |
| Hunker × no OW | No tax on sitting | YES — turtle meta |
| Fuse × Hunker turtle | Only reliable flush if sticks present | Conditional counter |
| Fuse × Rough | Flee MP fails across brush | YES — guaranteed blast |
| Fuse × −5.5 AI | Herd without detonating | YES — AI abuse |
| Rough × body-block | Choke 2× paths | YES — cheese |
| Rough × cover break | Permanent slow scar | YES — inverted incentive |
| Rough × raises | Slow adds to gunline | YES — farm assist |
| Deployed XP × raises | Full XP to active four | YES — **CRITICAL** |
| All four | Heavy moat, slow approaches, fuse denial, add conveyor, XP only on deployed | **Boss courtyard becomes a grind instance** |

---

## 7. WHAT THE BASELINES HIDE

BUILD RUN table (pos bot):

| change | deacon WR |
|---|---|
| base | .714 |
| + hunker ends | .744 |
| + rough | .772 |
| + fuse | .771 |
| + Deacon free raise | **.774** |

Reads as "safe, neutral kit." Lies:

1. Bot does not farm XP; harness measures win rate, not XP/duration/resources.
2. Bot brace banking ≠ human hunker-ends-turn cost.
3. Bot −5.5 fuse avoid ≠ human herding creativity.
4. Saturated non-boss rows still useless for buff detection.
5. Free raise ~neutral WR can still be **critical progression exploit**.

**Do not greenlight demo on .774.**

---

## 8. DEGENERATE DOMINANT LINES (player)

1. **Deacon courtyard grind:** ignore boss HP, clear raises on spawn, heavy+hunker, extract max XP, then finish. *Critical if enrage HP-gated + adds give XP.*
2. **Heavy parking lot:** first to heavy wins; hunker spam; wait for AI misstep. *High without OW/explosives.*
3. **Brush moat castle:** heavy + soft-cover ring; force 2× enter; plink.
4. **Stick shepherd (when player has sticks):** paint −5.5 zones / human-equivalent threat; walk enemies into LOS; optional detonation.
5. **Break light cover for scars** only when you want permanent slow, not when you want a fast assault path.

## 9. AI-ABUSE PATTERNS

1. Lit stick forces bot off objective (overweighted avoid).
2. Body-block rough tiles; pathfinder pays or loops.
3. Spawn-camp first free slot; deletes raises before they act.
4. Keep Deacon at 2 adds alive if that softens his offense more than it threatens you (cap softens raise pressure) — or keep 0 for max XP; choose by goal.
5. If shoot-then-brace still legal for bot only → instrument lies about player defense options.

## 10. STALL / FARM STRATEGIES

| Strategy | Requires | XP? | Risk |
|---|---|---|---|
| Add conveyor farm | Free raise + kill XP + survivable DPS | **5 XP/round gross** | Low on heavy |
| Pure time stall | Heavy + hunker | No (unless adds) | Softlock boredom |
| Fuse-herd cycle | Bandit sticks + choke | Indirect | Medium |
| Rough kite | Soft-cover belts + range | Indirect | Low |

---

## 11. REQUIRED ANSWERS FOR TIM (blockers)

1. **Do kit-raised walkin_dead grant the 10 XP kill?** If yes → close before demo.
2. **Enrage trigger:** HP, turn, damage-taken, other? HP-only + ignore-boss = infinite farm.
3. **AP + hunker mutex:** can you shoot then hunker same activation?
4. **Fuse on thrower death:** explode or fizzle?
5. **Rough after cover break:** intentional permanent scar?
6. **Bot brace banking:** identical rules to player hunker?

---

## 12. SEVERITY-ORDERED FIX LIST (advisory)

**P0 — ship-block if demo includes Deacon + XP:**
- Kit adds: 0 XP or hard XP budget per fight.
- Or enrage timer / anti-ignore (no free raises if Deacon unhurt for K turns).

**P1 — before tuning pass:**
- Confirm hunker/attack mutex; if AP≥3 without mutex, dominant line never died.
- Align bot brace with player rules or stop reading post-hunker WR.
- Fuse avoid: soft-cap or EV-based flee (damage − cover − objective), not flat −5.5 spam.
- Rough scar: remove double-MP when light cover destroyed, **or** mark scar intentional and retune spawn paths.

**P2 — design debt (known, still open):**
- OW / reaction still HELD → turtle and free-flank remain.
- Spawn slot randomness for Deacon.
- Instrument needs XP/duration metrics, not WR only.

---

## 13. ONE-LINE CLOSES

- **Farm:** real conveyor at **0.5 kills/Deacon activation → 5 XP/activation gross**; unbounded if enrage ignores pure stall and adds pay XP; deployed-only XP removes dilution brake.
- **Hunker:** ends-turn does not kill shoot-brace unless AP mutex says so; pure heavy turtle is the replacement dominant without OW.
- **Fuse:** herding is the feature; −5.5 + rough flee fail are the bugs.
- **Rough:** body-block and post-break scars cheese pathing; helps the Deacon farm.
- **Baselines:** .774 is not a clean bill of health.

— Njord
