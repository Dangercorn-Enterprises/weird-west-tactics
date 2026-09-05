#!/usr/bin/env node
// =============================================================================
// DUSTFALL — SMOKE TEST (DEV-ONLY; lives OUTSIDE src/, never shipped)
//
// Fast gate run by `npm test`:
//   1. Syntax-checks every shipped JS file (src/ + electron/) with node --check.
//   2. Requires the real data.js and asserts catalog/archetype integrity.
//   3. Runs the balance harness's core battle sim and asserts engine invariants
//      (hit clamps, reach costs, scaling floors, battles terminate).
//   4. Quick win-rate sanity: the default skirmish must be winnable and the
//      hardest boss must not be a guaranteed loss.
//   5. Persistent-wound regression against the SHIPPED src/scene_battle.js,
//      loaded headlessly (mirror of godot/tests/wound_test.gd).
// Exit 0 = green. Any assert failure prints and exits 1.
// =============================================================================
"use strict";
const { execFileSync } = require("child_process");
const fs = require("fs");
const path = require("path");

const ROOT = path.join(__dirname, "..");
let failures = 0;
function check(name, cond, detail) {
  if (cond) {
    console.log("  ok  " + name);
  } else {
    failures++;
    console.error("FAIL  " + name + (detail ? " — " + detail : ""));
  }
}

// ---- 1. syntax check all shipped JS ----------------------------------------
const jsFiles = [];
for (const dir of ["src", "electron", "tools"]) {
  const full = path.join(ROOT, dir);
  if (!fs.existsSync(full)) continue;
  fs.readdirSync(full)
    .filter((f) => f.endsWith(".js"))
    .forEach((f) => jsFiles.push(path.join(dir, f)));
}
console.log("syntax check (" + jsFiles.length + " files):");
for (const f of jsFiles) {
  try {
    execFileSync(process.execPath, ["--check", path.join(ROOT, f)], {
      stdio: "pipe",
    });
    console.log("  ok  " + f);
  } catch (e) {
    failures++;
    console.error("FAIL  " + f + "\n" + e.stderr.toString());
  }
}

// ---- 2. data integrity -------------------------------------------------------
const DATA = require(path.join(ROOT, "src", "data.js"));
console.log("data integrity:");
check("6 archetypes", DATA.ARCHETYPES.length === 6);
check(
  "every archetype has a primary weapon",
  DATA.ARCHETYPES.every((a) => a.weapons && a.weapons[0]),
);
check(
  "every archetype has a pregen",
  DATA.ARCHETYPES.every((a) => DATA.PREGEN[a.id]),
);
check("6 gods", DATA.GODS.length === 6);
check(
  "enemy catalog sane",
  DATA.ENEMY_CATALOG.every(
    (e) => e.hp > 0 && e.wmin >= 1 && e.wmax >= e.wmin && e.rng >= 1,
  ),
);
check(
  "5 bosses in catalog",
  DATA.ENEMY_CATALOG.filter((e) => e.boss).length === 5,
);

// ---- 3. engine invariants (via the harness's mirrored math) -----------------
const H = require(path.join(ROOT, "tools", "balance_harness.js"));
console.log("engine invariants:");
const grid = H.buildGrid();
const party = H.starterParty();
const pUnits = party.map((p, i) => H.partyToUnit(p, i));
const eSpec = DATA.ENEMY_CATALOG[0];
const eUnit = H.enemyToUnit(eSpec, 0);
eUnit.q = 8;
eUnit.r = 8;
// hit chance clamps 5..95 across extremes
const worst = H.hitChance(
  grid,
  Object.assign({}, pUnits[0], { aim: -500 }),
  eUnit,
);
const best = H.hitChance(
  grid,
  Object.assign({}, pUnits[0], { aim: 999 }),
  eUnit,
);
check("hitChance clamps low (5)", worst === 5, "got " + worst);
check("hitChance clamps high (95)", best === 95, "got " + best);
// damage roll bounded
let dmgOk = true;
for (let i = 0; i < 500; i++) {
  const d = H.rollDmg(pUnits[0]);
  const lo = pUnits[0].wmin + Math.floor(pUnits[0].str / 3);
  const hi = pUnits[0].wmax + Math.floor(pUnits[0].str / 3);
  if (d < lo || d > hi) dmgOk = false;
}
check("rollDmg stays in [wmin+str/3, wmax+str/3]", dmgOk);
// gear application (Pass 5/6): equipped store gear overrides defaults
const geared = H.partyToUnit(
  {
    uid: "g0",
    archetype: "gunslinger",
    stats: Object.assign({}, DATA.PREGEN.gunslinger.stats),
    gear: { weapon: "rifle", armor: "reinforced_vest" },
  },
  0,
);
check(
  "equipped Rifle applies (range 7)",
  geared.rng === 7,
  "got " + geared.rng,
);
check(
  "equipped Rifle damage 5-10",
  geared.wmin === 5 && geared.wmax === 10,
  geared.wmin + "-" + geared.wmax,
);
check("Reinforced Vest def 4 applies", geared.armorDef === 4);
check(
  "Vest speed -1 costs an AP (4→3)",
  geared.maxAp === 3,
  "got " + geared.maxAp,
);
// Forge mod (Pass 15): Ashfall Chamber on the default Peacemaker (4-8 → 4-10)
const modded = H.partyToUnit(
  {
    uid: "m0",
    archetype: "gunslinger",
    stats: Object.assign({}, DATA.PREGEN.gunslinger.stats),
    gear: { weapon: null, armor: null, mod: "ashfall_chamber" },
  },
  0,
);
check(
  "Ashfall Chamber +2 wmax applies",
  modded.wmax === 10 && modded.wmin === 4,
  modded.wmin + "-" + modded.wmax,
);

// battles terminate and produce coherent results
console.log("battle sim:");
let terminates = true,
  coherent = true;
for (let i = 0; i < 50; i++) {
  const res = H.runBattle(
    party,
    [DATA.ENEMY_CATALOG[0], DATA.ENEMY_CATALOG[2]],
    60,
  );
  if (res.timedOut) terminates = false;
  if (res.win && res.survivors < 1) coherent = false;
  if (!res.win && res.survivors > 0 && !res.timedOut) coherent = false;
}
check("battles terminate within 60 rounds", terminates);
check("win/survivor accounting coherent", coherent);

// ---- 4. quick win-rate sanity ------------------------------------------------
const quick = H.evalEncounter(
  "smoke: default skirmish",
  party,
  ["walkin_dead", "coyote_beast", "forge_sentry", "dust_devil"],
  300,
);
check(
  "default skirmish winnable (>60%)",
  quick.winRate > 0.6,
  (quick.winRate * 100).toFixed(1) + "%",
);
const boss = H.evalEncounter(
  "smoke: deacon",
  party,
  ["the_deacon", "walkin_dead", "walkin_dead", "coyote_beast"],
  300,
);
check(
  "Deacon boss beatable but not free (20-90%)",
  boss.winRate > 0.2 && boss.winRate < 0.9,
  (boss.winRate * 100).toFixed(1) + "%",
);

// ---- 5. persistent wounds (audit C1, 2026-09-04) — the SHIPPED battle scene --
// Mirror of godot/tests/wound_test.gd, run against src/scene_battle.js itself
// rather than the harness. Bug: mkUnit set maxHp = hp with hp already reduced
// by the rider's stored hpDamage, and finish() stores hpDamage = maxHp - hp, so
// any wound older than the last battle was silently healed and a fallen rider
// with prior wounds came back above 1 HP. Fix: maxHp is the TRUE max
// (10 + vigor*2). Tim's picks (2026-09-04): Fork A1 — in-battle heals cure
// campaign wounds; Fork B2 — a fallen rider who levels returns at 1 HP plus the
// vigor headroom (no 1-HP pin loop), symmetric with surviving riders.
// The real engine.js / scene_battle.js / scenes_hub.js are loaded headlessly on
// a minimal DOM stand-in; each battle runs enter() -> forceWin() -> finish(),
// then the real results scene awards XP. saveGame is a no-op (never touches a
// real save), matching the Godot test's MemoryState.
console.log("persistent wounds (src/scene_battle.js, headless):");
{
  // Stand-in DOM: real child lists (renderParty loops on firstChild), every
  // selector resolves to an element, the canvas context swallows every call.
  const CTX = new Proxy(
    {},
    {
      get: (t, k) => (k in t ? t[k] : () => {}),
      set: (t, k, v) => ((t[k] = v), true),
    },
  );
  class El {
    constructor() {
      this.children = [];
      this.style = {};
      this.classList = {
        add() {},
        remove() {},
        toggle() {},
        contains: () => false,
      };
      this.textContent = "";
    }
    get firstChild() {
      return this.children[0] || null;
    }
    appendChild(c) {
      this.children.push(c);
      return c;
    }
    removeChild(c) {
      const i = this.children.indexOf(c);
      if (i >= 0) this.children.splice(i, 1);
      return c;
    }
    querySelector() {
      return new El();
    }
    querySelectorAll() {
      return [];
    }
    addEventListener() {}
    removeEventListener() {}
    getAttribute() {
      return null;
    }
    setAttribute() {}
    getBoundingClientRect() {
      return { left: 0, top: 0, width: 900, height: 620 };
    }
    getContext() {
      return CTX;
    }
  }
  global.window = {
    DF: {},
    innerWidth: 0,
    innerHeight: 0,
    addEventListener() {},
    removeEventListener() {},
    requestAnimationFrame: () => 0,
  };
  global.document = {
    hidden: true,
    body: new El(),
    head: new El(),
    createElement: () => new El(),
    querySelector: () => new El(),
    querySelectorAll: () => [],
    addEventListener() {},
  };
  global.requestAnimationFrame = () => 0;
  global.localStorage = {
    setItem() {},
    getItem: () => null,
    removeItem() {},
  };
  // the classic scripts read the catalogs as bare globals (ARCHETYPES, BIOMES, ...)
  Object.assign(global, DATA);
  for (const f of ["engine.js", "scene_battle.js", "scenes_hub.js"])
    require(path.join(ROOT, "src", f));
  const DF = global.window.DF;
  DF.saveGame = () => {}; // MemoryState: the test never writes a save
  const battle = DF.scenes.battle;
  const results = DF.scenes.results;
  check(
    "battle + results scenes load headlessly",
    !!(battle && results && DF.battle),
  );

  // One battle: spawn the persistent roster, poke the gunslinger's in-battle
  // state, force the win, then run the results scene (XP share + level-ups).
  // Returns the gunslinger's and the enemies' state AS SPAWNED.
  const fight = (state, mutate) => {
    DF.state = state;
    battle.enter({ onComplete: () => {} });
    const u = DF.battle.players.find((p) => p.id === "p0");
    const spawned = {
      hp: u.hp,
      maxHp: u.maxHp,
      enemies: DF.battle.enemies.map((e) => ({ hp: e.hp, maxHp: e.maxHp })),
    };
    if (mutate) mutate(u);
    DF.battle.forceWin();
    results.enter(DF.battle.result);
    return spawned;
  };

  // Pregen gunslinger (Silas Crowe): vigor 5 -> true max 20. Carry an 8-point
  // wound in (start 12). Each case: one battle ending at `hp`/`alive`, then a
  // second battle with no new damage — the stored wound must be stable across
  // both. gunslinger FAVORED = deftness/quickness, so a level adds exactly +1
  // vigor (+2 max HP) with no RNG in the HP path. The forced win pays 25 XP,
  // split 2 ways (13 each): 99 + 13 crosses Lv 2, 0 + 13 + 13 never does.
  const CASES = [
    { name: "damage", hp: 10, alive: true, xp: 0, next: 10 },
    { name: "unchanged", hp: 12, alive: true, xp: 0, next: 12 },
    { name: "healed (A1)", hp: 16, alive: true, xp: 0, next: 16 },
    { name: "fallen", hp: -4, alive: false, xp: 0, next: 1 },
    { name: "fallen+level (B2)", hp: -4, alive: false, xp: 99, next: 3 },
  ];
  for (const c of CASES) {
    const party = DF.makeStarterParty(); // gunslinger + hexslinger
    const m = party[0];
    m.hpDamage = 8;
    m.xp = c.xp;
    const state = Object.assign(DF.newGame(), { party });
    const first = fight(state, (u) => {
      u.hp = c.hp;
      u.alive = c.alive;
    });
    check(
      c.name + ": max HP is the true max",
      first.maxHp === 20,
      "got " + first.maxHp,
    );
    check(
      c.name + ": start HP carries the wound",
      first.hp === 12,
      "got " + first.hp,
    );
    const second = fight(state);
    check(
      c.name + ": next battle HP",
      second.hp === c.next,
      "got " + second.hp,
    );
    if (c.name.startsWith("fallen+level")) {
      check(c.name + ": rider reached Lv 2", m.level === 2, "got " + m.level);
      check(
        c.name + ": max HP grew with vigor",
        second.maxHp === 22,
        "got " + second.maxHp,
      );
    }
    // A battle with no new damage must not move the wound.
    const third = fight(state);
    check(c.name + ": third battle HP", third.hp === c.next, "got " + third.hp);
  }

  // Rest/Doc clear hpDamage; a cleared rider spawns at full.
  {
    const party = DF.makeStarterParty();
    party[0].hpDamage = 0;
    const rested = fight(Object.assign(DF.newGame(), { party }));
    check("rest clears wounds", rested.hp === 20, "got " + rested.hp);
    // Enemies and summons never pass maxHp — mkUnit must still default it to hp.
    check(
      "mkUnit without maxHp defaults to hp",
      rested.enemies.length > 0 &&
        rested.enemies.every((e) => e.hp > 0 && e.maxHp === e.hp),
      JSON.stringify(rested.enemies),
    );
  }
}

console.log(
  failures === 0
    ? "\nSMOKE TEST GREEN (" + jsFiles.length + " files, all asserts passed)"
    : "\nSMOKE TEST RED — " + failures + " failure(s)",
);
process.exit(failures === 0 ? 0 : 1);
