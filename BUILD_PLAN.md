# Dustfall — Build Plan (vertical slice → shippable desktop game)

North star: build **Dustfall** into a playable vertical slice of a 16-bit tactical RPG that is on a clear path to ship as a **desktop game** (Steam / Epic / GoG).

## Working rules (every phase)
- Work entirely in `D:\Claude Projects\weird-west-tactics` on `main`.
- **Commit AND push after every phase** so nothing is lost.
- **Verify each phase live in the browser** with the preview tools using **scripted logic checks**, not just screenshots (that's how the v0.3 hit-chance bug got caught).
- Stay **canon to `DUSTFALL_BIBLE.md`**; reuse/extend `src/data.js`.
- Keep the game **runnable and playable at EVERY commit** — never leave it broken.
- Art is **programmatic 16-bit pixel art** in the bible's palette (FF4/FF6 look); **no external asset files**.
- Commit/push code to the repo; **no web deploy**.
- **Done** when the Phase 7 slice is real + verified and Phase 8 packaging stands up — or after **250 turns**. If blocked, mark it and continue; never stall. Bias toward a shippable coherent slice over half-built breadth.

## LOCKED COMBAT CORE (never change)
Combat stays the **isometric, elevation/height + cover tactical grid** already built in `src/dustfall-arena.html` (FFT/XCOM-style depth — the "3D feel"). The FF4/FF6 references are **ART and PALETTE ONLY** — how it LOOKS, never how combat WORKS. **No flat 2D side-view battles, ever.** The iso/elevation/cover battlefield is canon and gets *richer*, not replaced.

## SHIP TARGET (desktop game, not a website)
End product is a downloadable desktop game for **Steam/Epic/GoG**. Web tech is the **engine**; the browser is only the **dev/verify harness**. Build packaging-ready from day one:
- Runs **offline and self-contained** (loads from local files, NO runtime server or network calls).
- Saves go through a **tiny storage interface** that swaps `localStorage` (browser) ↔ filesystem (desktop).
- Render at a **fixed internal resolution scaled to the window** for fullscreen.
- Route input through an **abstraction** so gamepad can be added later.

## Phases (commit + push after each)

**PHASE 1 — Architecture & data.** Clean scene-based single-page game (World Map / Town / Battle / Results + shared state; save/load behind the storage interface) served by the existing `launch.json` for dev. Bring the v0.3 iso arena in **AS-IS** as the Battle scene (preserve its elevation + cover). Centralize ALL data in `src/data.js`: 9 stats; 6 archetypes + abilities + divine abilities; every weapon/armor/consumable/mod; all enemies (T1/T2/T3 with the bible's stats); the 6 gods/factions.

**PHASE 2 — Overworld = the real US Southwest.** Navigable parchment map, Oregon → Mexican border (N–S), offshore Catalina → Texas (E–W). MAJOR population centers + state capitals as nodes (LA, San Diego, SF, Sacramento, Reno, Carson City, Vegas, Phoenix, Tucson, Albuquerque, El Paso, Austin, San Antonio, Salt Lake City, Portland) PLUS nationally-iconic smaller sites mapped to a god's lore (Roswell→Sleeping One; Los Alamos & Hoover Dam→Vulcan; Death Valley & Tombstone→Samedi; Salton Sea/Scorch→Sleeping One; Marfa & Sedona→Coyote; Virginia City→Vulcan mining). Each node: name, real-geo position, owning god/faction (tinted zone), buildings, one-line lore hook tying its real fame to the mythology. Paths with travel time + risk + random encounters. Player token moves node→node.

**PHASE 3 — Town hubs.** Menu-driven (Saloon: rest/recruit/rumors; Outfitter: buy/sell; Shrine: pray/align/favor; Forge/Stables/Marshal/Doc where the bible says). Working gold economy, recruitment that adds roster units, inventory.

**PHASE 4 — Battle maturation + enemy balance** (on the locked iso/elevation/cover core). CT turn-order bar, full AP, all 6 archetypes with abilities + divine abilities, usable items, cover/height/Ashfall-tile mechanics, full damage formula, downed/bleed-out/revive, Results screen with XP. Implement AND balance every bible enemy (T1/T2/T3) with distinct per-faction AI; tune so early fights are winnable and bosses are hard.

**PHASE 5 — Progression.** XP→level up (+2 stats or +1 stat & new ability), divine favor + corruption tracking, loot/shop gear that changes stats, persistent roster across battles.

**PHASE 6 — Art & game-feel (RE-SKIN ONLY — combat format unchanged).** Apply a cohesive 16-bit FF4/FF6 pixel aesthetic — palette, sprites, portraits, UI — ON TOP OF the existing isometric elevation+cover battlefield. Pixel-art tiles for the iso grid (keep height stacking + cover props intact), sprite units with N/S/E/W facings, animated CT bar, floating damage numbers, particles, screenshake, parchment UI panels, divine-zone tinting, heat haze. SNES-era look; the iso/elevation/cover combat does NOT change.

**PHASE 7 — Vertical-slice wiring + verify.** Chain: start at a Southwest city → travel the map → enter a town → outfit/recruit → trigger a battle → win, gain XP, level up → return to map, with one reachable boss. Full in-browser playthrough verified via a scripted end-to-end check. Update `index.html` launcher + README.

**PHASE 8 — Desktop packaging (the ship path).** Add an Electron wrapper (main process loads the game from local files), `package.json` + electron-builder config + npm scripts, and route saves through Electron's userData path when packaged. Produce a Windows build if the toolchain installs cleanly; otherwise leave it one `npm run dist` away and document it. This proves Dustfall ships as a Steam/Epic/GoG desktop app, not a web page. **Do NOT create store accounts, pay fees, or wire the Steamworks SDK — flag those as Tim's next step.**

## If finished early
Deepen content: more enemies, a second fully-stocked town, a second iso battle map, the first campaign mission "The Claim."
