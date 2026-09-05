#!/usr/bin/env node
// =============================================================================
// DUSTFALL — GODOT<->NODE PARITY CHECK (DEV-ONLY)
// Runs the same encounters through the Node balance harness and through the
// Godot combat core (headless), then compares:
//   - unit derivations: EXACT match required
//   - encounter win rate / avg rounds / avg kills: EXACT match required
// Contract (bit-exact, since 2026-07-10): both sides seed the shared mulberry32
// stream with 1337 and make the same random draws in the same order, so every
// row must agree with delta 0.0. There is no tolerance. Any non-zero delta
// means a draw was added, removed or reordered on one side. Fix the drift,
// never loosen this gate. godot/scripts/combat_core.gd is canonical, and
// tools/balance_harness.js must mirror it draw for draw.
// Float comparison: the Godot side snaps its aggregates to 4 decimals
// (parity_test.gd, snappedf 0.0001) before printing, so the Node side is
// rounded to the same 4 decimals and the two are compared exactly.
// Usage: node tools/parity_check.js [path-to-godot-exe]
// =============================================================================
"use strict";
const { execFileSync } = require("child_process");
const path = require("path");
const ROOT = path.join(__dirname, "..");
const H = require(path.join(ROOT, "tools", "balance_harness.js"));

const RUNS = 2000;
// Both sides are compared at the precision the Godot side emits (4 decimals).
const r4 = (x) => Number(x.toFixed(4));

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

// ---- bit-exact encounter parity ---------------------------------------------
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
  "encounter win rate / rounds / kills (exact, " + RUNS + " runs/side):",
);
for (const [key, [pk, ids]] of Object.entries(ENC)) {
  const node = H.evalEncounter(key, parties[pk], ids, RUNS);
  const gd = g.encounters[key];
  // Shared seed + same draws -> exact. Compare at the 4 decimals Godot emits.
  const nWr = r4(node.winRate);
  const nR = r4(node.avgRounds);
  const nK = r4(node.avgKills);
  const gWr = r4(gd.wr);
  const gR = r4(gd.rounds);
  const gK = r4(gd.kills);
  const diff = Math.abs(nWr - gWr);
  // rounds/kills ride along (XP-inflow + stall visibility, WR can't see farms).
  const dR = Math.abs(nR - gR);
  const dK = Math.abs(nK - gK);
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
    nWr === gWr && nR === gR && nK === gK,
    "Δwr " +
      (diff * 100).toFixed(2) +
      "pts Δr " +
      dR.toFixed(4) +
      " Δk " +
      dK.toFixed(4),
  );
}

console.log(
  failures === 0
    ? "\nPARITY GREEN — the Godot core matches the shipped balance"
    : "\nPARITY RED — " + failures + " failure(s)",
);
process.exit(failures ? 1 : 0);
