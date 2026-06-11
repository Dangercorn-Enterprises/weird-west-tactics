#!/usr/bin/env node
/**
 * extract_haunt_spec.js
 *
 * Single source-of-truth export of the Haunt system.
 * Reads src/haunts.js (Node-exported), evaluates every haunt's roster
 * at each tier 1-5, and emits a clean engine-agnostic JSON spec at:
 *
 *    data/haunt_spec.json
 *
 * Consumers:
 *   - src/tactical-combat.html    — campaign-mode data loader (browser)
 *   - UEFN Verse scripts          — wave spawn specs (Fortnite Creative)
 *   - docs/HAUNT_WAVE_CATALOG.md  — human-readable reference
 *   - future: Claude/LLM planners — grounded input when composing quests
 *
 * Schema at `data/haunt_spec.json`:
 *   {
 *     version:   "0.1.0",
 *     generated: ISO timestamp,
 *     bestiary:  { [enemy_id]: { name, class, icon, stats, ... } },
 *     locations: { [location_id]: { name, description } },
 *     haunts:    [
 *       {
 *         id, name, tier, theme, location_ids: [], lore,
 *         special_rule: { name, description },
 *         roster_by_tier: {
 *           "1": [ { enemy_id, count } ],
 *           ...
 *           "5": [ ... ]
 *         },
 *         loot_table: [ { item, rarity, effect } ]
 *       }
 *     ]
 *   }
 */
const path = require("path");
const fs = require("fs");

const haunts = require(path.join(__dirname, "..", "src", "haunts.js"));
const { HAUNTS, HAUNTS_BESTIARY, HAUNT_LOCATIONS } = haunts;

const SPEC_VERSION = "0.1.0";
const TIERS = [1, 2, 3, 4, 5];

// ----- Bestiary ----------------------------------------------------------
// Emit a stable dict so tactical-combat.html + UEFN can pull by id.
const bestiary = {};
for (const [id, e] of Object.entries(HAUNTS_BESTIARY)) {
  bestiary[id] = {
    id,
    name: e.name,
    class: e.cls,
    icon: e.icon,
    tier: e.tier,
    stats: { ...e.stats },
    base_hp: e.hp,
    base_ap: e.ap,
    weapons: (e.weapons || []).map((w) => ({ ...w })),
    special: e.special || null,
    flavor: e.flavor || null,
  };
}

// ----- Locations ---------------------------------------------------------
const locations = {};
for (const [id, l] of Object.entries(HAUNT_LOCATIONS)) {
  locations[id] = {
    id,
    name: l.name,
    description: l.desc,
  };
}

// ----- Haunts with roster expanded per-tier ------------------------------
const haunts_out = HAUNTS.map((h) => {
  const roster_by_tier = {};
  for (const tier of TIERS) {
    const roster = typeof h.roster === "function" ? h.roster(tier) : h.roster;
    roster_by_tier[String(tier)] = roster.map((r) => ({
      enemy_id: r.tpl,
      count: r.count,
    }));
  }
  return {
    id: h.id,
    name: h.name,
    tier: h.tier,
    theme: h.theme,
    location_ids: h.locations || [],
    lore: h.lore || "",
    special_rule: h.special_rule || null,
    roster_by_tier,
    loot_table: h.loot_table || [],
  };
});

// ----- Validation: every roster enemy_id must exist in bestiary ----------
const errors = [];
for (const h of haunts_out) {
  for (const [tier, roster] of Object.entries(h.roster_by_tier)) {
    for (const entry of roster) {
      if (!bestiary[entry.enemy_id]) {
        errors.push(
          `haunt="${h.id}" tier=${tier}: unknown enemy_id "${entry.enemy_id}"`,
        );
      }
    }
  }
  for (const loc of h.location_ids) {
    if (!locations[loc]) {
      errors.push(`haunt="${h.id}": unknown location_id "${loc}"`);
    }
  }
}

if (errors.length) {
  console.error("SPEC VALIDATION FAILED:");
  for (const e of errors) console.error("  " + e);
  process.exit(2);
}

// ----- Emit --------------------------------------------------------------
const spec = {
  version: SPEC_VERSION,
  generated: new Date().toISOString(),
  generator: "tools/extract_haunt_spec.js",
  source: "src/haunts.js",
  counts: {
    bestiary: Object.keys(bestiary).length,
    locations: Object.keys(locations).length,
    haunts: haunts_out.length,
  },
  bestiary,
  locations,
  haunts: haunts_out,
};

const outPath = path.join(__dirname, "..", "data", "haunt_spec.json");
fs.writeFileSync(outPath, JSON.stringify(spec, null, 2) + "\n");
console.log(`✓ wrote ${outPath}`);
console.log(
  `  ${spec.counts.bestiary} enemies, ${spec.counts.locations} locations, ${spec.counts.haunts} haunts`,
);

// ----- Sanity summary to stdout ------------------------------------------
console.log("\n-- Haunt summary --");
for (const h of haunts_out) {
  const roster_counts = TIERS.map((t) => {
    const total = h.roster_by_tier[t].reduce((a, e) => a + e.count, 0);
    return `T${t}=${total}`;
  }).join(" ");
  console.log(
    `  [${h.tier}] ${h.id.padEnd(26)} ${h.theme.padEnd(11)} (${roster_counts})`,
  );
}
