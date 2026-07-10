# OVERWATCH — session brief (2026-07-10, for Tim's 2a design session)

*One page. Two argued positions + the cheap third door, a decision matrix,
and the parameter list whichever way you rule. Receipts: Njord red-teams #1
(§2a + "one thing missing") and #2 (§2 hunker turtle, §6 interaction matrix),
DESIGN_LOG Session #2 memo 2a + annex.*

## Why this is the load-bearing pick
Without reaction fire, flanking is free movement math (red-team #1), the
point-blank flank stays the only tax, and the heavy-cover turtle is the
replacement dominant line (red-team #2 §2 Hole B — hunker-ends-turn alone
doesn't close it). Fuse-delay herding also pays out double once a gun line
can punish the flushed move. Overwatch is the keystone that makes three
already-shipped systems (directional cover, hunker, fuse dynamite) bite.

## Position A — Calder: universal, capped, symmetric
Any unit may end its activation in **Overwatch** if it holds ≥2 AP: the AP
is reserved; the first enemy that MOVES through its LOS+range this enemy
phase eats one snap shot at −15 aim. One reaction per unit per round, both
sides, cancels on taking damage(?)— parameter. Ships together with a retune
pass (it will move every number; the dial map is ready).
- For: the full BattleTech/XCOM fire-support fantasy — hold the ridge, deny
  the ground. One universal rule, no per-kit bookkeeping. Closes turtle +
  free-flank in one stroke, symmetric so it can't buff only the over-band
  player (Njord's asymmetry catch, conceded).
- Against: biggest AI surface (enemies must respect threatened lanes or
  look dumb); stance UI + telegraphs; turn time; the retune is mandatory,
  not optional.

## Position B — Njord: kit ability first
**Covering Fire** on the units whose identity is holding ground — lawdog +
sentry-class enemies (turret later if Foreman's kit ships). Same trigger
mechanics, but only where the kit exists. Universal comes later, only with
caps + a planned retune.
- For: bounded AI (a few units), characterful, cheap to ship, reversible.
  Tests the whole reaction stack (triggers, UI, AI respect) at small scale
  before the game rebalances around it.
- Against: flanking stays free against most comps; the turtle meta is only
  partially taxed; if universal is the destination anyway, some of this is
  redone (Njord: acceptable; Calder: that redo risk is the real cost).

## The cheap third door — enter-adjacent snap (corrected trigger)
A free reaction shot when an enemy steps INTO adjacency. Not overwatch —
just makes the shipped point-blank flank cost blood. Ships in a day, no
stance UI, tiny AI. (The original memo's leave-melee trigger was wrong —
owned in the annex; enter-adjacent is the version that taxes the flank.)

## Njord's variants worth 10 minutes each
- **F — brace-overwatch hybrid:** units that didn't move get the reaction
  arc free ("hold the line") — couples elegantly with your hunker-mutex
  morning pick; one stance answers two open questions.
- **G — suppression, not damage:** reactions pin (−hit) instead of rolling
  kills — lower lethality variance, still taxes movement; friendlier to AI.

## Decision matrix

| axis | A universal-capped | B kit-first | enter-adjacent snap |
|---|---|---|---|
| taxes free flank | fully | vs some comps | point-blank only |
| closes heavy-turtle | yes (with fuse) | partially | no |
| AI scope | largest | bounded | trivial |
| UI/telegraph load | stance + lane hints | stance on few units | none |
| turn-time cost | real (capped helps) | small | none |
| forced retune | full pass | localized | ~none |
| BattleTech fantasy | the whole thing | flavored taste | none |
| redo risk if wrong | high | low | none (subsumed later) |
| pairs with fuse herding | maximal | partial | weak |

## Whichever way you rule — the parameter sheet (pick in-session)
trigger class (move-through-LOS vs leave-cover vs enter-range) · reaction
cap per unit per round (1 is sane) · snap aim penalty (−15 baseline) · AP
reserve cost (≥2) · does taking damage break the stance · does hunker
forbid or grant it (ties to the mutex pick) · suppression vs damage ·
who first (players+sentries vs everyone).

## After the pick (instrument plan, pre-committed)
Bot overwatch policy in BOTH engines (identical, no new RNG), parity re-run,
new baselines row, and a re-measure of: turtle stalemate rate, fuse-herd
value, and the hunker interaction — the dial map re-runs in minutes.
