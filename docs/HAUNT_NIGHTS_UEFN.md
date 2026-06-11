# Haunt Nights — a UEFN map as Dustfall funnel

*Design doc for a co-op horror wave-survival Fortnite Creative map that serves as the discovery surface for Dustfall: The Ashen Frontier. 40-hour scoped build with a kill switch at the deadline.*

## The pitch (30-second)

> Four riders wake in a dust-choked frontier town. The sun just set. The Haunts are coming. Hold the town till dawn — the 9:12 train to Denver leaves at first light, and if you miss it the Wendigo takes you.

**Genre:** Co-op horror + wave survival + rogue-lite (each run, different Haunts).
**Player count:** 4, matchmade or friends.
**Session length:** 18-25 minutes per run.
**Target audience inside Fortnite:** horror fans (largest UEFN genre by retention), L4D/Back4Blood refugees, Dead by Daylight crowd looking for PvE alternatives.

## Why Haunt Nights (not the other ideas)

Considered three concepts:

| Concept | Pro | Con | Pick |
|---|---|---|---|
| **Haunt Nights** (this) — co-op PvE horror | My 10 Haunts are literally pre-designed waves | Epic's horror slot is crowded | ★ |
| Ghost Rock Gunfight — PvP zone-wars | Faster streamer adoption | Would need custom weapon balancing & ranked-like retention | |
| Ashen Frontier Hub — sandbox RPG | Closest to Dustfall's core | 3× the scope. 120+ hour build. | |

Haunt Nights wins because **it is already designed** — `src/haunts.js` has 10 complete encounter templates with rosters, mechanics, lore, and loot. The UEFN port is a 1:1 translation, not new design. That compresses 30% of the schedule.

## Direct reuse from existing Dustfall work

From `src/haunts.js` I already have:

**15 enemies ready to translate to Fortnite NPC analogs:**
Walkin' Dead → Zombies (already in Fortnite asset library)
Prairie Wraith → Phantom enemies (UEFN has a ghost AI template)
Hellstromme Drone → Clockwork automaton (craft from the robotic-guard UEFN prefab)
Boiler Walker → Boss-tier explosive enemy
Ghost Rider, Void Eye, Wendigo, Thunderbird Fledgling, Dustskin, Iron Scorpion, Gravedigger, Preacher's Shadow, Rattlesnake Bill, Sheriff McClure, Outlaw Grunt

**10 haunt templates that map 1:1 to waves:**
- Wave 1 (easy intro): **The Hanging Tree** — outlaw grunts in rocks (cover-focused gunfight tutorial)
- Wave 2: **The Dust Storm** — Rattlesnake Bill + grunts, sight range capped 3 tiles
- Wave 3: **The Drowned Preacher** — first supernatural wave, Preacher's Shadow aura debuffs
- Wave 4: **The Iron Graveyard** — automaton wave, ghost-rock buff/debuff zones
- Wave 5 (boss): **Thunder Roost** — Thunderbird Fledgling (flying, lightning-strike mechanic)
- Escape: **The 9:12 from Hellstromme** — train arrives, moving platform mechanic, hold until departure

Each wave already has **a special rule** in the Haunts system that translates to UEFN:
- Holy Ground (Drowned Preacher) = buff zone
- Zero Visibility (Dust Storm) = fog VFX device
- Electric Air (Thunder Roost) = zap damage device with random strikes
- Moving Train (9:12) = UEFN mover device + hold-zone timer

## The Dustfall funnel

Every player who plays this map gets 3-5 deliberate Dustfall touchpoints:

1. **Loading screen art** — the Ashen Frontier title card + "A tactical RPG plays in your browser. dangercorn.net/dustfall"
2. **Character select** — they pick one of the 6 Dustfall archetypes (Gunslinger/Hexslinger/Tinkerer/Preacher/Law Dog/Drifter). Classes have Fortnite-weapon loadout + one ability matching the archetype (e.g. Tinkerer deploys a turret, Preacher's "Lay on Hands" heals teammates). Each archetype pick plays a 4-second voiceover quoting the Dustfall lore.
3. **Lore drops in-map** — interactable signs / journals in Dust Town. Reading one opens a short text panel from the Dustfall Bible with the credit "full lore: dangercorn.net/dustfall"
4. **End-of-run screen** — survivors get a "Your Posse Survived" screen with the 6 archetypes they could have picked, a preview image of the browser-game UI, and a **direct link** (via Fortnite's link device) to play Dustfall in a browser
5. **Credits crawl** — "Created by Dangercorn Enterprises. Play Dustfall free: dangercorn.net/dustfall. Discord: [link]"

The key numerate metric: **CTR from Fortnite session → browser Dustfall page.** UEFN link devices report click-through; aim for 3-5% on end-of-run screen (industry normal 1-2%).

## 40-hour build scope (milestones)

Hard kill switch if we hit 40h and don't have a minimum-viable playable map.

### Hours 0-4 — Setup + scouting
- Create Epic Games account, UEFN install, link Creator ID (you have dangercorn.net domain for verification)
- Clone an existing UEFN horror-survival template ([UEFN Horror Starter](https://create.fortnite.com) has one — saves ~10 hours of boilerplate)
- Inventory available assets: check Fortnite's Western prop kit (cabins, railroad, saloon, cacti), Unreal Marketplace for anything missing
- Design doc: confirm 5-wave scope, weapon loadouts per archetype, map blockout on paper

### Hours 4-12 — Map blockout + core loop
- Build Dust Town layout: 4 defendable buildings, a central square, 2 escape routes
- Place spawner devices for Waves 1-5
- Rig the player-archetype-select flow (6 pedestals in a lobby room, each with a pickup weapon + Verse script to assign class)
- Rig the wave-progression device chain (Wave 1 cleared → spawn Wave 2 with a 30-sec prep)
- Core gun-play: works out of the box with Fortnite's weapon system; only Verse-tune cooldowns

### Hours 12-24 — Haunt-specific mechanics
- **Wave 3 (Drowned Preacher aura)**: buff device + VFX prop
- **Wave 4 (Ghost Rock zones)**: custom volume triggers with Verse for heal/damage ticks
- **Wave 5 (Thunderbird)**: boss pathfinder + random lightning-strike script (Verse, ~50 lines)
- **Escape (9:12 train)**: mover device with a platform prop, timed departure, "hold the train" zone
- Test each mechanic in isolation before stacking

### Hours 24-32 — Dustfall funnel integration
- Loading screen + Dust Town signage + journals (flavor text from DUSTFALL_BIBLE.md)
- End-of-run screen with link devices → dangercorn.net/dustfall
- Archetype voiceover lines (6 × 4 sec each; can self-record or use ElevenLabs)
- Credits crawl

### Hours 32-38 — Playtest + tune
- 3-5 external friends playtest (record sessions)
- Tune difficulty — target: casual 4-stacks clear Wave 5 ~40% of the time (not 0%, not 90%)
- Fix the 5 most-broken things from playtest notes
- Publish a short trailer (< 30 sec) for the featured-map submission

### Hours 38-40 — Submit + ship
- Submit for Epic's featured placement review (requires content rating, island code, thumbnail)
- Write Discord announcement
- Tweet from @starmexxx's vein but Dangercorn-flavored
- Go/no-go assessment: does the map play well? Is the funnel obvious? Kill or continue.

## Success metrics (at hour 40)

**Go signals (continue iterating):**
- ✅ 4-player coop run is replayable — playtesters want to go again
- ✅ At least 1 of the 5 waves produces clippable "oh shit" moments
- ✅ Link-click-through on end-screen > 3% in playtests
- ✅ Trailer clip gets > 5% hook rate (time-to-first-swipe)

**Kill signals (stop, recoup hours):**
- ❌ Core loop boring after one run — retention dead
- ❌ Funnel unclear — playtesters don't remember "Dustfall" when asked post-run
- ❌ Technical issues requiring >20% more scope to fix
- ❌ Discover tab surfaces maps far bigger than ours; we're invisible

## Risk register

| Risk | Mitigation |
|---|---|
| UEFN asset library lacks weird-western props | Use Fortnite's standard Western pack + procedural placement; don't try to import custom 3D. |
| Verse scripting rabbit hole for boss AI (Thunderbird) | Timebox each custom Verse feature to 4 hours max. Fall back to device-only mechanics if time runs. |
| Epic rejects for "low effort" | Include a polished trailer and unique hook ("weird western horror roguelite" is not a saturated tag). Use the Dustfall Bible lore in-map as proof of depth. |
| 40 hours is too tight | Weekly checkpoints — if hour 24 milestone slips, cut to 3 waves instead of 5. Ship small rather than miss the window. |
| No playtest group | Post in UEFN creator Discord for playtesters — common practice, fast yield. |

## Out of scope for v1 (save for v2+)

- Multiple maps (Red Canyon, Sanitarium)
- Persistent XP between runs
- Daily-leaderboard racing
- Multi-night campaign mode
- Ashen Frontier hub world (that's Option C, not Option A)

## If it hits — what v2 looks like

If v1 clears the go-signals at hour 40, v2 adds:
- Second map: **The Cold Mine** (wendigo-themed, uses existing mine asset pack)
- Daily rotating "featured haunt" mechanic — map plays different each night
- Leaderboards tied to each archetype
- Cosmetic "haunt badges" earned on clear, visible in lobby

## Non-negotiables

- **Browser Dustfall stays free, no paywalls.** UEFN map is the funnel; Dustfall monetization comes from elsewhere (optional cosmetic packs, art commissions by Jess).
- **No actual purchase asks in the UEFN map.** UEFN's creator-economy payout is the only monetization on Fortnite side.
- **40-hour budget is the budget.** If we're at hour 60 with no ship, it's a cautionary tale, not "just one more weekend."

## First three concrete next steps

1. **Install UEFN + create Epic Creator account** on Legion (~30 min)
2. **Download the UEFN Horror Survival Starter template** from fab.com / UEFN samples (~20 min)
3. **Blockout Dust Town in UEFN** — 4 buildings + 1 central square + spawn points (~3 hours)

After these three, you'll know within 4 hours whether the platform feels workable.

---

*Doc v0.1, drafted 2026-04-23. Update as build progresses — this is a living plan.*
