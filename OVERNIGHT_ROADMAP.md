# Dustfall — Overnight Maturation Roadmap (advance the finished slice)

**Context:** `BUILD_PLAN.md`'s 8 phases are DONE (commits `f487064`→`2b2d077`): scene-based SPA, US-Southwest overworld, town hubs, the battle scene wrapping the locked iso arena, archetype abilities, XP/leveling, a 16-bit art pass, and Electron packaging. This roadmap **matures that working slice** — depth, content, polish, balance. It is NOT a rebuild.

## RULE ZERO — survey before you build
Before ANY change: `git log --oneline -20`, read the existing files (`engine.js`, `scene_battle.js`, `scene_worldmap.js`, `scene_town.js`, `scenes_hub.js`, `worldmap_data.js`, `data.js`, `game.html`), and **boot the game in-browser** to see current state. NEVER redo finished work or clobber an existing file. (Tonight a careless pass created a redundant `data_canon.js` and nearly overwrote a more-complete `engine.js` — do not repeat that.)

## Standing rules
- **Legion is free overnight — USE the preview server + browser.** Verify every increment in-browser with **scripted logic checks** (drive the real game functions, not just screenshots — that's how the `hitChance` NaN got caught).
- **Commit AND push after every increment.** Keep the game runnable + playable at EVERY commit.
- Stay canon to `DUSTFALL_BIBLE.md`; extend the EXISTING code, don't reinvent.
- **LOCKED COMBAT CORE** unchanged: isometric elevation+cover tactical grid; FF4/FF6 = art/palette only, never a 2D-battle format change.
- **SHIP TARGET:** offline, self-contained, packageable desktop game (Steam/Epic/GoG). No web deploy; commit to repo.
- Bias **depth + polish of a coherent, playable game** over half-built breadth. If blocked, mark it and continue — never stall.

## Maturation tracks (priority order)
1. **BASELINE** — boot + scripted-verify the current slice plays end-to-end (worldmap→town→battle→results→level→back). Fix anything broken first; commit a known-good baseline.
2. **BATTLE DEPTH** (core loop, highest value) — all 6 archetypes playable with abilities + divine abilities (bible §4); CT turn-order bar (charge-time) if absent; overwatch/hunker/use-item in combat; downed→bleed-out→revive; full damage formula. 2–3 distinct iso battle maps beyond the single arena. Wire the full bestiary (T1/T2/T3) into encounters with distinct per-faction AI; balance so early fights are winnable, bosses hard. At least one multi-phase **boss** (a T3) playable.
3. **OVERWORLD DEPTH** — render the real US-Southwest node map (positions, divine-zone tinting, per-node lore hooks from `worldmap_data.js`); node→node travel with fog + random encounters; travel time / day counter.
4. **TOWN + ECONOMY** — Saloon recruits real units into the persistent roster; Outfitter buy/sell that actually changes a unit's weapon/armor/stats; Shrine = choose a god → unlock that divine ability + track favor; working gold economy.
5. **PROGRESSION** — XP→level (bible: +2 stats, or +1 & new ability), gear affecting stats, divine favor + corruption, persistent roster across battles; save/load verified across a full session.
6. **CAMPAIGN SPINE** — wire bible Act 1 as a playable chain: "The Claim" (tutorial) → street fight → old mine (first undead) → company men (faction choice) → boss **The Deacon**. Even abbreviated, make it playable start→first boss. This turns the slice into a GAME.
7. **ART & GAME-FEEL** — deepen the 16-bit FF4/FF6 aesthetic across all scenes (unit/portrait sprites, parchment overworld, town UI, battle juice) — within the locked iso combat.
8. **SHIP-READINESS** — with Legion free, verify Phase 8 truly builds: `npm install` + `npm run dist` (Electron) produces a runnable Windows package; fix what breaks; document the result. Do NOT create store accounts or pay fees (Tim's step).

## Done-when
A genuinely deep, polished, playable Dustfall — Act 1 playable to its first boss, all 6 archetypes usable, real overworld + town economy + progression, every increment verified in-browser, and the Electron desktop build confirmed to produce a runnable app — OR ~350 turns. Stop when no clearly high-value increment remains; don't pad. Leave a morning summary at `…/memory/dustfall_overnight_2026-06-16.md`: what shipped, commit hashes, what's next, anything blocked.
