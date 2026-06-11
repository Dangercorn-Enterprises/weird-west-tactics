# Haunt Wave Catalog

*Auto-generated from `data/haunt_spec.json` v0.1.0. Do not edit by hand — run `tools/render_wave_catalog.js` after changing `src/haunts.js`.*

Single source of truth for:
- `src/tactical-combat.html` campaign-mode encounter loader
- UEFN wave-spawn specs ("Haunt Nights" Fortnite Creative map)
- Claude/LLM encounter planners (grounded input)

**Totals:** 15 enemies · 6 locations · 10 haunts.

---

## Bestiary

| ID | Name | Class | Tier | HP | AP | Stats | Weapons | Special |
|---|---|---|---:|---:|---:|---|---|---|
| `outlaw_grunt` | 🤠 Saddle Bum | Outlaw | 1 | 10 | 4 | def=5 nim=4 qui=4 vig=4 spi=3 | **Rusted Pistol** (d 3-6, r5, ap2, acc55); **Knife** (d 2-5, r1, ap1, acc75) | — |
| `walking_dead` | 💀 Walkin' Dead | Undead | 1 | 12 | 3 | def=3 nim=3 qui=3 vig=8 spi=1 | **Rusty Claws** (d 3-6, r1, ap1, acc70) | — |
| `hellstromme_drone` | 🤖 Hellstromme Drone | Automaton | 2 | 20 | 3 | def=6 nim=2 qui=4 vig=10 spi=0 | **Steam Cannon** (d 6-14, r5, ap2, acc55); **Crushing Arm** (d 4-8, r1, ap1, acc75) | — |
| `rattlesnake_bill` | 🐍 Rattlesnake Bill | Outlaw | 2 | 16 | 4 | def=7 nim=6 qui=6 vig=5 spi=4 | **Winchester** (d 4-9, r7, ap2, acc70); **Boot Knife** (d 2-5, r1, ap1, acc80) | — |
| `wraith` | 👻 Prairie Wraith | Undead | 2 | 8 | 5 | def=5 nim=9 qui=9 vig=3 spi=8 | **Spectral Claw** (d 2-7, r1, ap1, acc85) | Ignores cover. Immune to normal bullets (needs Spirit-infused weapons or Hex Bolts). |
| `ghost_rider` | 🐎 Ghost Rider | Harrowed | 3 | 18 | 6 | def=7 nim=8 qui=9 vig=5 spi=7 | **Flaming Lance** (d 5-11, r2, ap2, acc75) | Moves 2 tiles per 1 AP (mounted). Leaves a 1-tile fire trail behind. |
| `gravedigger` | ⚰ The Gravedigger | Undead | 3 | 22 | 4 | def=5 nim=4 qui=4 vig=12 spi=6 | **Rusted Shovel** (d 5-10, r1, ap2, acc80); **Grave Dust** (d 3-5, r3, ap1, acc65) | Heals 2 HP per turn while adjacent to a corpse. |
| `iron_scorpion` | 🦂 Iron Scorpion | Automaton | 3 | 14 | 5 | def=7 nim=6 qui=7 vig=6 spi=0 | **Venom Dart** (d 3-7, r4, ap1, acc75); **Stinger** (d 5-9, r1, ap2, acc80) | Dart injects a toxin — target loses 1 AP next turn. |
| `preachers_shadow` | 🕯 Preacher's Shadow | Harrowed | 3 | 14 | 4 | def=5 nim=7 qui=7 vig=4 spi=9 | **Unholy Words** (d 4-8, r4, ap2, acc70) | Players within 2 tiles suffer -2 to their accuracy (prayer-cloud aura). |
| `boiler_walker` | 🔥 Boiler Walker | Automaton | 4 | 32 | 3 | def=4 nim=1 qui=3 vig=14 spi=0 | **Flamethrower** (d 7-12, r3, ap3, acc70); **Steam Vent** (d 4-6, r2, ap1, acc85) | When HP drops below 25%, explodes on its next turn for 10-18 damage in 2-tile radius. |
| `dustskin` | 🌫 Dustskin | Eldritch | 4 | 22 | 4 | def=4 nim=8 qui=6 vig=7 spi=8 | **Suffocating Grasp** (d 4-8, r1, ap2, acc80) | Half damage from bullets (dust reconstitutes). Full damage from fire or spirit weapons. |
| `the_sheriff` | ⭐ Sheriff McClure | Outlaw | 4 | 24 | 5 | def=8 nim=5 qui=6 vig=7 spi=6 | **Long Colt** (d 5-10, r6, ap2, acc80); **Sawed-Off** (d 4-9, r3, ap2, acc75) | Rallies adjacent outlaws: +10 accuracy to their next shot. |
| `thunderbird_chick` | 🦅 Thunderbird Fledgling | Myth | 4 | 16 | 6 | def=6 nim=9 qui=9 vig=5 spi=6 | **Lightning Cry** (d 4-9, r5, ap2, acc70); **Talons** (d 3-6, r1, ap1, acc80) | Flying — ignores terrain. Thunderclap (once per fight): stuns all within 2 tiles for 1 turn. |
| `void_eye` | 👁 Void Eye | Eldritch | 4 | 8 | 3 | def=2 nim=2 qui=4 vig=3 spi=10 | **Gaze** (d 3-9, r6, ap1, acc90) | Looking at it costs 1 Spirit per turn. Cannot be blinded. Ignores cover. |
| `wendigo` | 🦌 Wendigo | Myth | 5 | 36 | 5 | def=5 nim=7 qui=6 vig=12 spi=7 | **Hunger** (d 7-14, r1, ap2, acc75) | Inflicts 'Cold Dread' on hit: target loses 1 Spirit permanently (save on Spirit check). |

### Flavor (for readable lore drops in-map)

- **Saddle Bum** — *A rider who chose the wrong trail. Still chose it, though.*
- **Walkin' Dead** — *Shambling, hungry, and patient. Bullets don't kill what was never alive.*
- **Hellstromme Drone** — *Built in Pittsburgh from ghost-rock and brass. You can hear it a mile off.*
- **Rattlesnake Bill** — *Thirty-seven notches on his rifle. He'll take your notch count too.*
- **Prairie Wraith** — *Cold breath on your neck. Then nothing. Then the bleeding starts.*
- **Ghost Rider** — *A rider whose horse died and rode on anyway.*
- **The Gravedigger** — *He buries them. Then he unburies them. Then they follow him.*
- **Iron Scorpion** — *A clockwork thing with a soul the size of a pinhead. It doesn't tire.*
- **Preacher's Shadow** — *What's left of a man who broke a vow to something older than God.*
- **Boiler Walker** — *The shell holds steam at eight times pressure. You do the math.*
- **Dustskin** — *It wears a man's shape, filled with the sand of forty graves.*
- **Sheriff McClure** — *Wears a star that hasn't meant anything in ten years.*
- **Thunderbird Fledgling** — *Its parent hasn't returned yet. It's hungry. It's angry.*
- **Void Eye** — *It's not an animal. It's the IDEA of being seen. It should not be here.*
- **Wendigo** — *Once a man. Then he ate his kin. Now he cannot stop.*

---

## Locations

| ID | Name | Description |
|---|---|---|
| `dust_town` | Dust Town | A dying settlement. Broken buildings, narrow streets. |
| `canyon` | Red Canyon | High walls, sharp drops, abundant cover behind rocks. |
| `rail_line` | The Rail Line | A stretch of the Transcontinental. Exposed, windy. |
| `ghost_rock_mine` | Ghost-Rock Mine | Tunnels and shafts, ghost-rock veins everywhere. |
| `prairie` | Open Prairie | Flat grassland. Minimal cover. Long sight lines. |
| `sanitarium` | The Sanitarium | A ruin that was a hospital. Or was it? |

---

## Haunts (encounter templates)

Each is a complete encounter: lore, location options, special rule, per-tier roster, loot on victory.

### `outlaw_ambush` — The Hanging Tree

- **Tier:** 1
- **Theme:** `frontier`
- **Locations:** `prairie`

> A man swings from the big oak. He's been there a week. Watching. His friends are in the rocks.

**Special rule — Cover Rich:** All rocks on the map provide +30% cover (normal: 20%).

**Roster scaling:**

| Tier | Enemies |
|---:|---|
| 1 | 4× Saddle Bum |
| 2 | 5× Saddle Bum |
| 3 | 6× Saddle Bum |
| 4 | 7× Saddle Bum |
| 5 | 8× Saddle Bum |

**Loot on victory:**

- _common_ — **Outlaw's Boots**: +1 movement on dirt tiles
- _uncommon_ — **Noose**: Used as a rope tool: climb walls or lasso (1 AP)


### `dust_storm_ambush` — The Dust Storm

- **Tier:** 2
- **Theme:** `frontier`
- **Locations:** `prairie`, `dust_town`

> A twister rolls in out of the south. Bandits use the cover. You don't.

**Special rule — Zero Visibility:** Sight range capped at 3 tiles. Ranged attacks beyond 3 tiles auto-miss. Stealth class bonuses doubled.

**Roster scaling:**

| Tier | Enemies |
|---:|---|
| 1 | 1× Rattlesnake Bill, 4× Saddle Bum |
| 2 | 1× Rattlesnake Bill, 5× Saddle Bum |
| 3 | 1× Rattlesnake Bill, 6× Saddle Bum |
| 4 | 1× Rattlesnake Bill, 7× Saddle Bum |
| 5 | 1× Rattlesnake Bill, 8× Saddle Bum |

**Loot on victory:**

- _common_ — **Bandit Cache**: $50 or 1 weapon mod
- _uncommon_ — **Rattlesnake's Bandana**: +1 accuracy in dust storms


### `drowned_preacher` — The Drowned Preacher

- **Tier:** 3
- **Theme:** `undead`
- **Locations:** `dust_town`, `sanitarium`

> The flood came in 1872. Pastor Whitt stood on the pulpit as the water rose. He's still preaching.

**Special rule — Holy Ground:** If the Preacher is defeated while a player occupies the pulpit tile (center of map), that player gains +1 to all Spirit checks for the rest of the campaign.

**Roster scaling:**

| Tier | Enemies |
|---:|---|
| 1 | 1× Preacher's Shadow, 2× Walkin' Dead |
| 2 | 1× Preacher's Shadow, 3× Walkin' Dead |
| 3 | 1× Preacher's Shadow, 3× Walkin' Dead |
| 4 | 1× Preacher's Shadow, 4× Walkin' Dead |
| 5 | 1× Preacher's Shadow, 4× Walkin' Dead |

**Loot on victory:**

- _uncommon_ — **Waterlogged Bible**: +1 Spirit once per rest
- _rare_ — **Silver Cross**: Spirit-weapon tag on melee attacks


### `failed_experiment` — The Failed Experiment

- **Tier:** 3
- **Theme:** `automaton`
- **Locations:** `sanitarium`

> Dr. Strycker's lab went quiet six months ago. The rumbling, however, never stopped. Someone should check.

**Special rule — Steam Pipes:** Attacking a pipe tile (highlighted) vents scalding steam, dealing 4-8 damage in 3-tile area and destroying the pipe.

**Roster scaling:**

| Tier | Enemies |
|---:|---|
| 1 | 1× Hellstromme Drone, 2× Iron Scorpion, 0× Boiler Walker |
| 2 | 1× Hellstromme Drone, 3× Iron Scorpion, 0× Boiler Walker |
| 3 | 1× Hellstromme Drone, 3× Iron Scorpion, 0× Boiler Walker |
| 4 | 1× Hellstromme Drone, 4× Iron Scorpion, 1× Boiler Walker |
| 5 | 1× Hellstromme Drone, 4× Iron Scorpion, 2× Boiler Walker |

**Loot on victory:**

- _rare_ — **Dr. Strycker's Notes**: Tinkerer unlocks 'Arc Pistol' upgrade
- _common_ — **Gear Assembly**: Crafting component


### `the_last_sermon` — The Last Sermon

- **Tier:** 3
- **Theme:** `undead`
- **Locations:** `dust_town`, `sanitarium`

> The congregation gathers every Sunday. They died in 1879. They are still here.

**Special rule — Sacred Echo:** Preacher-archetype players gain +2 damage and can cast Lay on Hands at 0 AP cost. Others suffer -1 Spirit while in the church.

**Roster scaling:**

| Tier | Enemies |
|---:|---|
| 1 | 1× Preacher's Shadow, 4× Walkin' Dead, 1× The Gravedigger |
| 2 | 1× Preacher's Shadow, 5× Walkin' Dead, 1× The Gravedigger |
| 3 | 1× Preacher's Shadow, 5× Walkin' Dead, 1× The Gravedigger |
| 4 | 1× Preacher's Shadow, 6× Walkin' Dead, 1× The Gravedigger |
| 5 | 1× Preacher's Shadow, 6× Walkin' Dead, 1× The Gravedigger |

**Loot on victory:**

- _uncommon_ — **Tarnished Chalice**: Heal 2 HP once per rest
- _rare_ — **The Sermon Book**: Preacher learns 'Holy Smite'


### `cold_mine` — The Cold Mine

- **Tier:** 4
- **Theme:** `myth`
- **Locations:** `ghost_rock_mine`

> The miners came out and wouldn't stop shivering. The ones who went back in never came out.

**Special rule — Cold Dread:** Every player loses 1 Spirit per round (save on 3+ d6). At 0 Spirit, player becomes 'Numb' — cannot use abilities but takes -2 damage.

**Roster scaling:**

| Tier | Enemies |
|---:|---|
| 1 | 1× Wendigo, 2× Prairie Wraith |
| 2 | 1× Wendigo, 2× Prairie Wraith |
| 3 | 1× Wendigo, 3× Prairie Wraith |
| 4 | 1× Wendigo, 3× Prairie Wraith |
| 5 | 1× Wendigo, 3× Prairie Wraith |

**Loot on victory:**

- _rare_ — **Wendigo Claw**: +2 damage to Myth-class enemies
- _common_ — **Miner's Flask**: Removes one Cold Dread stack per use


### `iron_graveyard` — The Iron Graveyard

- **Tier:** 4
- **Theme:** `automaton`
- **Locations:** `canyon`, `ghost_rock_mine`

> Hellstromme Industries buried its failures out here. The failures kept working.

**Special rule — Ghost-Rock Veins:** Highlighted tiles are ghost-rock outcrops. Standing on one restores 1 AP at turn start, but deals 2 HP/turn (radiation).

**Roster scaling:**

| Tier | Enemies |
|---:|---|
| 1 | 1× Boiler Walker, 2× Hellstromme Drone, 1× Iron Scorpion |
| 2 | 1× Boiler Walker, 2× Hellstromme Drone, 1× Iron Scorpion |
| 3 | 1× Boiler Walker, 2× Hellstromme Drone, 1× Iron Scorpion |
| 4 | 1× Boiler Walker, 2× Hellstromme Drone, 2× Iron Scorpion |
| 5 | 1× Boiler Walker, 2× Hellstromme Drone, 3× Iron Scorpion |

**Loot on victory:**

- _common_ — **Raw Ghost-Rock**: Crafting component
- _rare_ — **Intact Drone Core**: Tinkerer can build a turret in 1 turn (vs 3)


### `the_9_12_from_hellstromme` — The 9:12 from Hellstromme

- **Tier:** 4
- **Theme:** `harrowed`
- **Locations:** `rail_line`

> The train left Pittsburgh on time. It has not arrived. You are on it now. The conductor punches your ticket — three red holes.

**Special rule — Moving Train:** The map scrolls 1 tile toward the left each enemy turn. Units that fall off the east edge are Gone.

**Roster scaling:**

| Tier | Enemies |
|---:|---|
| 1 | 1× Ghost Rider, 3× Walkin' Dead, 1× Prairie Wraith |
| 2 | 1× Ghost Rider, 3× Walkin' Dead, 1× Prairie Wraith |
| 3 | 1× Ghost Rider, 3× Walkin' Dead, 2× Prairie Wraith |
| 4 | 1× Ghost Rider, 3× Walkin' Dead, 2× Prairie Wraith |
| 5 | 1× Ghost Rider, 3× Walkin' Dead, 2× Prairie Wraith |

**Loot on victory:**

- _rare_ — **Conductor's Watch**: +3 initiative on first turn (Quick Draw stacks)
- _uncommon_ — **Engineer's Cap**: Immune to Cold Dread


### `cracked_earth` — Cracked Earth

- **Tier:** 5
- **Theme:** `eldritch`
- **Locations:** `canyon`, `ghost_rock_mine`

> The canyon opened wider last night. Things crawled out. They wear our shapes but they are not ours.

**Special rule — Reality Thin:** At the end of each round, roll 1d6 per player. On a 1, that player swaps positions with a random unit on the map. On a 6, gains 1 AP next turn.

**Roster scaling:**

| Tier | Enemies |
|---:|---|
| 1 | 2× Void Eye, 2× Dustskin, 1× Wendigo |
| 2 | 2× Void Eye, 2× Dustskin, 1× Wendigo |
| 3 | 2× Void Eye, 2× Dustskin, 1× Wendigo |
| 4 | 2× Void Eye, 2× Dustskin, 1× Wendigo |
| 5 | 2× Void Eye, 2× Dustskin, 1× Wendigo |

**Loot on victory:**

- _legendary_ — **Fragment of Elsewhere**: Once per session: relocate any unit 5 tiles
- _rare_ — **Dust-Silk Scarf**: Immune to one status effect per encounter


### `thunder_roost` — Thunder Roost

- **Tier:** 5
- **Theme:** `myth`
- **Locations:** `canyon`, `prairie`

> The elders warned you. The rocks are thunder-stones; this is the Thunderbird's nest. Something is very hungry.

**Special rule — Electric Air:** Every ranged weapon fired gets +10% crit chance but -10% accuracy. Metal armor: 50% chance to draw one Lightning Cry automatically to the wearer per turn.

**Roster scaling:**

| Tier | Enemies |
|---:|---|
| 1 | 1× Thunderbird Fledgling, 2× Prairie Wraith |
| 2 | 1× Thunderbird Fledgling, 2× Prairie Wraith |
| 3 | 1× Thunderbird Fledgling, 2× Prairie Wraith |
| 4 | 1× Thunderbird Fledgling, 2× Prairie Wraith |
| 5 | 1× Thunderbird Fledgling, 2× Prairie Wraith |

**Loot on victory:**

- _legendary_ — **Thunder-stone**: +2 damage to all electrical/lightning attacks
- _rare_ — **Fledgling Feather**: Grants 1 use of 'Flight' (move across impassable terrain)


---

## Haunt Nights — UEFN 5-wave loadout

This is the specific sequence for the Fortnite map build ([HAUNT_NIGHTS_UEFN.md](./HAUNT_NIGHTS_UEFN.md)). Difficulty ramps from ambush to boss.

| Wave | Haunt | Hook | Clip-moment |
|---:|---|---|---|
| 1 | `outlaw_ambush` — The Hanging Tree | Cover-focused gunfight tutorial | Rattlesnake's first shot whizzing past |
| 2 | `dust_storm_ambush` — The Dust Storm | Zero visibility | Enemies emerging from the haze |
| 3 | `drowned_preacher` — The Drowned Preacher | First supernatural aura | Preacher's Shadow debuff floor |
| 4 | `iron_graveyard` — The Iron Graveyard | Ghost-rock buff/debuff zones | Boiler Walker explosion countdown |
| 5 | `thunder_roost` — Thunder Roost (BOSS) | Lightning storm | Thunderbird's Thunderclap stun |
| Escape | `the_9_12_from_hellstromme` | Moving train | Leaving a teammate behind at the wrong second |

Each wave's special rule maps to a UEFN device:
- **Holy Ground / Ghost-rock vein** → Volume Device + VFX prefab
- **Zero Visibility** → Fog device + sight-limit zone
- **Electric Air** → Damage Volume with random trigger
- **Moving Train** → Mover device + hold-zone timer

---

## How to consume this programmatically

### Browser (tactical-combat.html)
```js
fetch('data/haunt_spec.json').then(r => r.json()).then(spec => {
  const haunt = spec.haunts.find(h => h.id === 'cold_mine');
  const roster = haunt.roster_by_tier['3'];
  // roster: [{ enemy_id: 'wendigo', count: 1 }, { enemy_id: 'wraith', count: 3 }]
  const wendigo = spec.bestiary[roster[0].enemy_id];
  spawnEnemy(wendigo, { x: 10, y: 5 });
});
```

### UEFN / Verse
```verse
# At build time, haunt_spec.json is baked into a Verse class table.
# At runtime, look up the wave by id, iterate roster, spawn prefab per enemy_id.
wave_spec := WaveSpec{HauntId := "drowned_preacher", Tier := 3}
for (enemy : GetRoster(wave_spec)):
    SpawnEnemy(GetBestiaryEntry(enemy.EnemyId), SpawnPoint)
```

### LLM planner (Claude)
Load `data/haunt_spec.json` into the prompt context. Claude can then compose new encounters by id-referencing existing enemies + locations + rules instead of inventing lore mid-stream.

---

*Generated 2026-04-24T01:30:16.210Z from src/haunts.js v0.1.0.*
