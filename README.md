# Dustfall: The Ashen Frontier

A turn-based tactical RPG set in a supernatural weird western world — inspired by games like XCOM, Fallout Tactics, and classic tabletop RPG systems.

**Status:** Playable vertical slice (worldmap · towns · iso combat · leveling) — Active Development

## ▶ Play

Open `index.html` (or `src/game.html` directly) in a browser, or run the dev server: `npx serve src`, then visit `/game.html`.

**The vertical slice loop:** Title → travel the **US-Southwest overworld** (Oregon→Mexico, offshore Catalina→Texas; major cities + lore-famous sites, each bound to one of six warring gods) → **town hubs** (saloon recruit/rest/rumors, outfitter, shrine, marshal bounties — a live gold economy) → **isometric tactical combat** (elevation + cover, AP, six archetype abilities, healing, divine powers) → **results, XP & leveling** → back to the map. First arrival at a tier-3 node triggers a **boss reckoning**.

**Architecture (ship-ready):** offline, self-contained, classic-script SPA — `src/game.html` + `engine.js` (scene manager / state / storage / scaling) + per-scene files + `data.js`/`worldmap_data.js`. Web tech is the engine; the game packages to a desktop app for **Steam / Epic / GoG** via Electron (`electron/`). Full build plan in `BUILD_PLAN.md`.

## What Is This?

A browser-based tactical combat game where you command a posse of gunslingers, mystics, and mad inventors against supernatural horrors in a post-apocalyptic weird western setting. Think XCOM meets the Wild West with steampunk and the occult.

## Features (Current)

- **Character Creator** — Build custom characters with archetype selection, point-buy stat allocation, and an edges/hindrances system
- **Tactical Combat** — Grid-based turn-based combat with action points, cover mechanics, hit probability, and overwatch
- **6 Character Archetypes** — Gunslinger, Hexslinger, Tinkerer, Preacher, Law Dog, Drifter
- **Character Import** — Create characters in the builder, export as JSON, import into tactical combat
- **Enemy AI** — Basic threat assessment and tactical movement
- **Combat Abilities** — Healing, turret deployment, overwatch, hunker down

## Features (Planned)

- [ ] Original world lore and mythology (in development)
- [ ] Expanded map editor
- [ ] Multiple mission types
- [ ] Loot and inventory system
- [ ] Campaign progression
- [ ] 3D visual upgrade
- [ ] Sound design and music

## How To Play

1. Open `index.html` in any modern browser
2. Choose to create a custom character, import a saved one, or pick a pre-built character
3. Select your posse (up to 3 characters)
4. Enter tactical combat
5. Click units to select → choose actions → click tiles to execute
6. Keyboard: `Tab` = cycle units, `Escape` = cancel action, `E` = end turn

## Tech Stack

Pure HTML/CSS/JavaScript — no frameworks, no build tools, no dependencies. Opens in any browser.

## About

This is an active passion project exploring game design and development through iterative prototyping. Built as a proof of concept for a larger tactical RPG vision.

## Part of Dangercorn Enterprises

Built by [Dangercorn Enterprises](https://github.com/Dangercorn-Enterprises).

## License

MIT
