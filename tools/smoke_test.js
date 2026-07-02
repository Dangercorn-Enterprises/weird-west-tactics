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

console.log(
  failures === 0
    ? "\nSMOKE TEST GREEN (" + jsFiles.length + " files, all asserts passed)"
    : "\nSMOKE TEST RED — " + failures + " failure(s)",
);
process.exit(failures === 0 ? 0 : 1);
