# THE FRONTIER REMEMBERS — rival layer brief (Lane D, 2026-10-08, for Tim's pick)

*Pillar P3 (DESIGN_PILLARS.md): "named rivals who survive, scar, escalate, and
hold grudges; a world that reacts." Tim named the Nemesis system unprompted in
his canon. Three designed options, what each reuses, the patent line, and the
sub-picks I need. Nothing built; this is a design session on paper.*

## What already exists to build on (receipts)
- **Marshal board** (town.gd `_marshal`, scene_town.js `marshal`): the only
  repeatable income; bounty = 60 + 40 x tier; enemies drawn from the catalog
  by town tier. A rival is a bounty with a name.
- **Trail ambushes** (worldmap.gd ~281): risk-based roll per leg, pool by
  tier, mount modifies the odds. A rival is an ambush that chose you.
- **Enemy temperaments** (combat_core enemy_to_unit): swarm / cover / flank /
  sentry / teleport / bomber / tank / hexer / zealot / boss kits. A rival's
  "personality" is a temperament plus a grudge target.
- **haunts.js** (unwired): themes, locations, special rules, loot tables,
  seeded generator. A rival's lair is a haunt.
- **Character-creator hindrances** `wanted` ("bounty hunters pursue you") and
  `haunted` — statted, never implemented. `wanted` IS the rival layer's hook.
- **Campaign state** `flags`, `act1-3.step`, wounds (hpDamage), `last_result`.
- **The sim instrument** can measure a rival's fight; it cannot measure
  drama. This layer gets a playtest gate, not a win-rate gate.

## Option A — Wanted-poster rivals (characters first; smallest)
A rival is MINTED by a notable event, not pre-authored. Candidate mint
triggers (sub-pick 1): an enemy downs a rider; an enemy survives a fight you
lost; a random "named" spawn in ambushes at tier 2+. The minted unit gets a
generated name + epithet (lore_engine.py already writes hooks), +1 rank
(hp/aim bump, one extra temperament), and a GRUDGE: a rider id the AI
prefers to target. Rivals live in `state.rivals[]` with rank, scars,
grudge, last-seen node. They surface three ways: on the marshal board as a
posted bounty (gold scales with rank), in trail ambushes near their
last-seen node (weighted), and as the leader of an ambush roster. Each fight
they SURVIVE (you lose, you wipe, or they are the last one standing when the
party is downed) escalates rank and adds a scar; each fight they LOSE is
permanent: the bounty pays, the poster comes down, a unique drop (ties into
the loot B decision) and a saloon rumor about it. Cap 3 live rivals.
+ smallest build (state + mint hook in apply_battle_result + two spawn
  hooks + board rows + a name table); reuses everything above; characters,
  not maps (Tim's canon); readable in one poster.
- no world reaction beyond the rival; rivals are only ever enemies.

## Option B — Faction ledger (the world reacts; New Vegas)
Six god-factions keep a reputation score from your choices: who you swear
to, which bounties you take, whose shrines you donate to, whose faithful
you kill. Reputation gates shop stock (Vulcan sells the Exo only to the
Vulcan-aligned, already half there), ambush pools (hostile factions hunt
you), favor prices, and rumor tone. + the "world that reacts" half of P3;
feeds P4 (six gods, six rulebooks). − broad and quiet: a number drifting in
a menu, not a face; needs UI to be felt; more data than code.

## Option C — Storyteller director (RimWorld)
A pacing AI with a tension curve picks the next event on each travel leg:
ambush, rival appearance, blessing, haunt, rumor, weather. haunts.js is the
event catalog seed; rivals (A) and reputation (B) become inputs. + the
replayability engine; emergent drama by construction. − the biggest build;
needs A or B to have anything to direct; hardest to playtest early.

## The patent line (WB, "Nemesis" family, granted 2021, runs to ~2035)
What is claimed is the HIERARCHY: non-player characters organized in ranks
who fight each other for promotion, with the player's actions moving them
up and down a visible org chart. Option A deliberately has NO hierarchy, no
promotion among enemies, no enemy-vs-enemy power struggle: it is a wanted
poster ledger — individuals with a rank number that only the player's
fights change, posted on a board, hunted or hunting. Keep it that way:
never add "captains who command other rivals" or rivals contesting each
other's rank. That is both the legal line and the better western.

## Recommendation
**A, then B, then C.** A is the one that puts a face on the frontier and
it is a week, not a quarter. B is the natural second layer once rivals
exist to be faction-flavored. C only makes sense with A and B as inputs.

## Sub-picks for A (needed before I prototype)
1. **What mints a rival:** downs a rider (recommended: the grudge is earned
   both ways) / survives a fight you lost / random named spawn at tier 2+ /
   any combination.
2. **Where rivals show up:** marshal board only / board + trail ambushes
   near their last-seen node (recommended) / also as story-beat leaders.
3. **Scars:** cosmetic (name + poster art) / mechanical (lost an eye: -aim,
   +grudge; recommended: both, small numbers) .
4. **Escalation cap and count:** rank 1-3, max 3 live rivals (recommended).
5. **The `wanted` hindrance:** wire it to double mint odds (recommended) or
   leave it dead for now.
