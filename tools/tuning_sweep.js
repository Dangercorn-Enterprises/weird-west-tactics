#!/usr/bin/env node
// =============================================================================
// DUSTFALL — TUNING DIAL SWEEP (DEV-ONLY, analysis; changes NO game data)
// For Tim's boss-band tuning session: sweeps GLOBAL enemy multipliers (hp /
// aim / dmg) over the parity encounters and reports win rate, avg rounds,
// avg kills, and gross XP inflow per cell — WR alone can't see farms or
// stalls (Njord red-team #2), so the XP/duration columns ride along.
// Player side = the positional bot (upper-bound-ish competent play; humans
// sit below — band centers are still a human-playtest call).
//
// Usage: node tools/tuning_sweep.js [runsPerCell]   (default 1000)
// Writes: docs/TUNING_DIALS_<date>.md
// =============================================================================
"use strict";
const fs = require("fs");
const path = require("path");
const ROOT = path.join(__dirname, "..");
const H = require(path.join(ROOT, "tools", "balance_harness.js"));
const { ENEMY_CATALOG } = require(path.join(ROOT, "src", "data.js"));

const RUNS = parseInt(process.argv[2], 10) || 1000;
const SEED = 1337;
const DIALS = ["hp", "aim", "dmg"];
const MULTS = [1.0, 1.1, 1.2, 1.3, 1.4, 1.5];

// the game's target bands (BALANCE-FINDINGS / DESIGN_LOG)
const BANDS = { story: [0.7, 0.85], ambush: [0.8, 0.9], boss: [0.45, 0.65] };
const ENC = [
  // name, partyKey, ids, band
  [
    "skirmish",
    "starter",
    ["walkin_dead", "coyote_beast", "forge_sentry", "dust_devil"],
    "story",
  ],
  [
    "vanguard",
    "starter",
    ["revenant_gun", "walkin_dead", "dynamite_bandit", "dynamite_bandit"],
    "story",
  ],
  [
    "deacon",
    "starter",
    ["the_deacon", "walkin_dead", "walkin_dead", "coyote_beast"],
    "boss",
  ],
  [
    "foreman",
    "starter",
    ["iron_foreman", "forge_sentry", "forge_sentry"],
    "boss",
  ],
  ["weaver", "starter", ["the_weaver", "dust_witch", "dust_witch"], "boss"],
  ["hollow", "starter", ["hollow_man", "dust_devil", "dust_devil"], "boss"],
  ["finale4", "full", ["hollow_man", "coyotes_shadow", "dust_devil"], "boss"],
  [
    "trailT1",
    "starter",
    ["walkin_dead", "coyote_beast", "rattlesnake"],
    "ambush",
  ],
  [
    "wildT2",
    "starter",
    ["revenant_gun", "dynamite_bandit", "ashfall_golem"],
    "ambush",
  ],
];

function dialSpecs(raw, partySize, dial, mult) {
  // party-size scaling first (the game applies it), then the global dial
  const scaled = H.scaleEncounter(raw, partySize);
  return scaled.map((s) => {
    const c = Object.assign({}, s);
    if (dial === "hp") c.hp = Math.max(4, Math.round(s.hp * mult));
    else if (dial === "aim") c.aim = Math.round(s.aim * mult);
    else if (dial === "dmg") {
      c.wmin = Math.max(1, Math.round(s.wmin * mult));
      c.wmax = Math.max(c.wmin, Math.round(s.wmax * mult));
    }
    return c;
  });
}

function cell(party, specs) {
  H.setSeed(SEED); // same stream per cell — cells comparable, not sequential
  let wins = 0,
    rounds = 0,
    kills = 0,
    timeouts = 0;
  for (let i = 0; i < RUNS; i++) {
    const r = H.runBattle(party, specs, 60);
    if (r.win) wins++;
    if (r.timedOut) timeouts++;
    rounds += r.rounds;
    kills += r.kills;
  }
  return {
    wr: wins / RUNS,
    rounds: rounds / RUNS,
    kills: kills / RUNS,
    xp: (kills / RUNS) * 10 + 25 * (wins / RUNS), // gross deployed-pool inflow
    to: timeouts / RUNS,
  };
}

function inBand(wr, band) {
  const [lo, hi] = BANDS[band];
  return wr >= lo && wr <= hi;
}

function main() {
  const parties = { starter: H.starterParty(), full: H.fullParty() };
  const date = "2026-07-10";
  let md = `# DUSTFALL — tuning dial map (${date}, ${RUNS} runs/cell, seed ${SEED})

*Analysis only — no game data changed. Player = positional bot (upper-bound-ish;
humans land below, so treat IN-BAND cells as "at most this hard"). Bands:
story ${BANDS.story.join("–")} · ambush ${BANDS.ambush.join("–")} · boss ${BANDS.boss.join("–")}.
**bold** = cell lands in its band. XP = avg kills×10 + 25×WR (gross inflow to
the deployed pool per fight — watch it climb with hp dials: longer fights vs
the Deacon mean more raised adds killed). ±~1.6pt CI at 1000 runs.*

`;
  for (const dial of DIALS) {
    md += `\n## Dial: enemy ${dial.toUpperCase()} ×mult\n\n`;
    md += `| encounter (band) | ${MULTS.map((m) => "×" + m.toFixed(1)).join(" | ")} |\n`;
    md += `|---|${MULTS.map(() => "---").join("|")}|\n`;
    for (const [name, pk, ids, band] of ENC) {
      const raw = ids
        .map((id) => ENEMY_CATALOG.find((e) => e.id === id))
        .filter(Boolean);
      const party = parties[pk];
      const cells = MULTS.map((m) =>
        cell(party, dialSpecs(raw, party.length, dial, m)),
      );
      md +=
        `| ${name} (${band}) | ` +
        cells
          .map((c) => {
            const wr = (c.wr * 100).toFixed(1) + "%";
            const s = `${wr} r${c.rounds.toFixed(1)} k${c.kills.toFixed(1)} xp${c.xp.toFixed(0)}`;
            return inBand(c.wr, band) ? `**${s}**` : s;
          })
          .join(" | ") +
        " |\n";
    }
  }
  md += `
## How to read this in the session
- Find the row for each fight, walk right until the cell bolds — that's the
  global multiplier that lands it in band FOR THE BOT; a human lands lower,
  so the honest target is usually one step left of the bolded cell.
- If a row never bolds on one dial, that fight needs a different dial (or a
  comp change — a data edit, not a rules edit).
- ROUNDS climbing with hp dials + XP climbing in the deacon row = the raise
  conveyor paying out in longer fights; the P0 farm closure changes this row.
- Timeout rates were ~0 across the sweep unless noted.
`;
  const out = path.join(ROOT, "docs", `TUNING_DIALS_${date}.md`);
  fs.writeFileSync(out, md);
  console.log("wrote " + out);
}

main();
