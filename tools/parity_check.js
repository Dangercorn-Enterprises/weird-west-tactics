#!/usr/bin/env node
// =============================================================================
// DUSTFALL — GODOT<->NODE PARITY CHECK (DEV-ONLY)
// Runs the same encounters through the Node balance harness and through the
// Godot combat core (headless), then compares:
//   - unit derivations: EXACT match required
//   - encounter win rates: within TOLERANCE (independent RNG streams)
// Usage: node tools/parity_check.js [path-to-godot-exe]
// =============================================================================
"use strict";
const { execFileSync } = require("child_process");
const path = require("path");
const ROOT = path.join(__dirname, "..");
const H = require(path.join(ROOT, "tools", "balance_harness.js"));

const TOLERANCE = 0.04; // 4 pts on 2000 runs (~3-sigma for p≈0.5)
const RUNS = 2000;

const godot =
  process.argv[2] ||
  process.env.GODOT ||
  "C:/Users/theja/AppData/Local/Microsoft/WinGet/Packages/GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe/Godot_v4.7-stable_win64_console.exe";

let failures = 0;
const check = (name, cond, detail) => {
  if (cond) console.log("  ok  " + name + (detail ? "  (" + detail + ")" : ""));
  else {
    failures++;
    console.error("FAIL  " + name + (detail ? " — " + detail : ""));
  }
};

// ---- run the Godot side -----------------------------------------------------
console.log("running Godot headless parity test (this takes a minute)...");
const raw = execFileSync(
  godot,
  [
    "--headless",
    "--path",
    path.join(ROOT, "godot"),
    "--script",
    "res://tests/parity_test.gd",
  ],
  { encoding: "utf8", timeout: 600000 },
);
const jsonLine = raw.split("\n").find((l) => l.trim().startsWith("{"));
if (!jsonLine) {
  console.error("no JSON from Godot. Output was:\n" + raw);
  process.exit(1);
}
const g = JSON.parse(jsonLine);
H.setSeed(1337); // deterministic node side — parity must not flake

// ---- exact unit derivations ---------------------------------------------------
const party = H.starterParty();
const u0 = H.partyToUnit(party[0], 0);
const geared = H.partyToUnit(
  {
    uid: "g0",
    archetype: "gunslinger",
    stats: Object.assign(
      {},
      require(path.join(ROOT, "src", "data.js")).PREGEN.gunslinger.stats,
    ),
    gear: { weapon: "rifle", armor: "reinforced_vest", mod: "ashfall_chamber" },
  },
  0,
);
console.log("unit derivations (exact):");
check(
  "gunslinger hp",
  g.unit.gunslinger_hp === u0.hp,
  g.unit.gunslinger_hp + " vs " + u0.hp,
);
check(
  "gunslinger aim",
  g.unit.gunslinger_aim === u0.aim,
  g.unit.gunslinger_aim + " vs " + u0.aim,
);
check("gunslinger maxAp", g.unit.gunslinger_maxAp === u0.maxAp);
check("gunslinger rng", g.unit.gunslinger_rng === u0.rng);
check("geared rng", g.unit.geared_rng === geared.rng);
check(
  "geared dmg",
  g.unit.geared_wmin === geared.wmin && g.unit.geared_wmax === geared.wmax,
  g.unit.geared_wmin +
    "-" +
    g.unit.geared_wmax +
    " vs " +
    geared.wmin +
    "-" +
    geared.wmax,
);
check("geared maxAp", g.unit.geared_maxAp === geared.maxAp);
check("geared armorDef", g.unit.geared_armorDef === geared.armorDef);
check("hit clamps", g.unit.hit_clamp_lo === 5 && g.unit.hit_clamp_hi === 95);

// ---- statistical win-rate parity ---------------------------------------------
const ENC = {
  skirmish: [
    "starter",
    ["walkin_dead", "coyote_beast", "forge_sentry", "dust_devil"],
  ],
  vanguard: [
    "starter",
    ["revenant_gun", "walkin_dead", "dynamite_bandit", "dynamite_bandit"],
  ],
  deacon: [
    "starter",
    ["the_deacon", "walkin_dead", "walkin_dead", "coyote_beast"],
  ],
  foreman: ["starter", ["iron_foreman", "forge_sentry", "forge_sentry"]],
  weaver: ["starter", ["the_weaver", "dust_witch", "dust_witch"]],
  hollow: ["starter", ["hollow_man", "dust_devil", "dust_devil"]],
  finale4: ["full", ["hollow_man", "coyotes_shadow", "dust_devil"]],
};
const parties = { starter: H.starterParty(), full: H.fullParty() };
console.log(
  "encounter win rates (±" + TOLERANCE * 100 + " pts, " + RUNS + " runs/side):",
);
for (const [key, [pk, ids]] of Object.entries(ENC)) {
  const node = H.evalEncounter(key, parties[pk], ids, RUNS);
  const gd = g.encounters[key];
  const diff = Math.abs(node.winRate - gd.wr);
  // rounds/kills ride along (XP-inflow + stall visibility — WR can't see
  // farms). Same seed + same draws -> effectively exact; 0.05 = float dust.
  const dR = Math.abs(node.avgRounds - gd.rounds);
  const dK = Math.abs(node.avgKills - gd.kills);
  check(
    key.padEnd(9) +
      " node " +
      (node.winRate * 100).toFixed(1) +
      "% / godot " +
      (gd.wr * 100).toFixed(1) +
      "%  r" +
      gd.rounds.toFixed(1) +
      " k" +
      gd.kills.toFixed(2),
    diff <= TOLERANCE && dR <= 0.05 && dK <= 0.05,
    "Δwr " +
      (diff * 100).toFixed(1) +
      "pts Δr " +
      dR.toFixed(3) +
      " Δk " +
      dK.toFixed(3),
  );
}

console.log(
  failures === 0
    ? "\nPARITY GREEN — the Godot core matches the shipped balance"
    : "\nPARITY RED — " + failures + " failure(s)",
);
process.exit(failures ? 1 : 0);
