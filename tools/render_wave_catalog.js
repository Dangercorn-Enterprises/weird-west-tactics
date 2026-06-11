#!/usr/bin/env node
/**
 * render_wave_catalog.js
 *
 * Reads data/haunt_spec.json and emits docs/HAUNT_WAVE_CATALOG.md —
 * a single-page reference for whoever's building UEFN waves (or campaign
 * mode for the browser game). Every table is navigable by either humans
 * or Ctrl-F.
 */
const path = require("path");
const fs = require("fs");

const specPath = path.join(__dirname, "..", "data", "haunt_spec.json");
if (!fs.existsSync(specPath)) {
  console.error(`MISSING: ${specPath}. Run extract_haunt_spec.js first.`);
  process.exit(1);
}
const spec = JSON.parse(fs.readFileSync(specPath, "utf8"));

const out = [];
const p = (s = "") => out.push(s);

p("# Haunt Wave Catalog");
p("");
p(
  `*Auto-generated from \`data/haunt_spec.json\` v${spec.version}. Do not edit by hand — run \`tools/render_wave_catalog.js\` after changing \`src/haunts.js\`.*`,
);
p("");
p("Single source of truth for:");
p("- `src/tactical-combat.html` campaign-mode encounter loader");
p('- UEFN wave-spawn specs ("Haunt Nights" Fortnite Creative map)');
p("- Claude/LLM encounter planners (grounded input)");
p("");
p(
  `**Totals:** ${spec.counts.bestiary} enemies · ${spec.counts.locations} locations · ${spec.counts.haunts} haunts.`,
);
p("");
p("---");
p("");

// --- Bestiary ------------------------------------------------------------
p("## Bestiary");
p("");
p("| ID | Name | Class | Tier | HP | AP | Stats | Weapons | Special |");
p("|---|---|---|---:|---:|---:|---|---|---|");
const sortedEnemies = Object.values(spec.bestiary).sort(
  (a, b) => a.tier - b.tier || a.id.localeCompare(b.id),
);
for (const e of sortedEnemies) {
  const stats = Object.entries(e.stats)
    .map(([k, v]) => `${k.slice(0, 3)}=${v}`)
    .join(" ");
  const weapons = e.weapons
    .map(
      (w) =>
        `**${w.name}** (d ${w.damage[0]}-${w.damage[1]}, r${w.range}, ap${w.apCost}, acc${w.accuracy})`,
    )
    .join("; ");
  const special = (e.special || "—").replace(/\|/g, "\\|");
  p(
    `| \`${e.id}\` | ${e.icon} ${e.name} | ${e.class} | ${e.tier} | ${e.base_hp} | ${e.base_ap} | ${stats} | ${weapons} | ${special} |`,
  );
}
p("");
p("### Flavor (for readable lore drops in-map)");
p("");
for (const e of sortedEnemies) {
  if (e.flavor) p(`- **${e.name}** — *${e.flavor}*`);
}
p("");

// --- Locations -----------------------------------------------------------
p("---");
p("");
p("## Locations");
p("");
p("| ID | Name | Description |");
p("|---|---|---|");
for (const l of Object.values(spec.locations)) {
  p(`| \`${l.id}\` | ${l.name} | ${l.description} |`);
}
p("");

// --- Haunts --------------------------------------------------------------
p("---");
p("");
p("## Haunts (encounter templates)");
p("");
p(
  "Each is a complete encounter: lore, location options, special rule, per-tier roster, loot on victory.",
);
p("");

const hauntsSorted = [...spec.haunts].sort(
  (a, b) => a.tier - b.tier || a.id.localeCompare(b.id),
);

for (const h of hauntsSorted) {
  p(`### \`${h.id}\` — ${h.name}`);
  p("");
  p(`- **Tier:** ${h.tier}`);
  p(`- **Theme:** \`${h.theme}\``);
  p(`- **Locations:** ${h.location_ids.map((l) => `\`${l}\``).join(", ")}`);
  p("");
  p(`> ${h.lore}`);
  p("");
  if (h.special_rule) {
    p(`**Special rule — ${h.special_rule.name}:** ${h.special_rule.desc}`);
    p("");
  }
  p(`**Roster scaling:**`);
  p("");
  p(`| Tier | Enemies |`);
  p(`|---:|---|`);
  for (const tier of [1, 2, 3, 4, 5]) {
    const roster = h.roster_by_tier[String(tier)];
    const line = roster
      .map(
        (r) => `${r.count}× ${spec.bestiary[r.enemy_id]?.name || r.enemy_id}`,
      )
      .join(", ");
    p(`| ${tier} | ${line || "—"} |`);
  }
  p("");
  if (h.loot_table && h.loot_table.length) {
    p(`**Loot on victory:**`);
    p("");
    for (const item of h.loot_table) {
      p(`- _${item.rarity}_ — **${item.item}**: ${item.effect}`);
    }
    p("");
  }
  p("");
}

// --- Haunt Nights: the UEFN 5-wave picked loadout ------------------------
p("---");
p("");
p("## Haunt Nights — UEFN 5-wave loadout");
p("");
p(
  "This is the specific sequence for the Fortnite map build ([HAUNT_NIGHTS_UEFN.md](./HAUNT_NIGHTS_UEFN.md)). Difficulty ramps from ambush to boss.",
);
p("");
p("| Wave | Haunt | Hook | Clip-moment |");
p("|---:|---|---|---|");
p(
  "| 1 | `outlaw_ambush` — The Hanging Tree | Cover-focused gunfight tutorial | Rattlesnake's first shot whizzing past |",
);
p(
  "| 2 | `dust_storm_ambush` — The Dust Storm | Zero visibility | Enemies emerging from the haze |",
);
p(
  "| 3 | `drowned_preacher` — The Drowned Preacher | First supernatural aura | Preacher's Shadow debuff floor |",
);
p(
  "| 4 | `iron_graveyard` — The Iron Graveyard | Ghost-rock buff/debuff zones | Boiler Walker explosion countdown |",
);
p(
  "| 5 | `thunder_roost` — Thunder Roost (BOSS) | Lightning storm | Thunderbird's Thunderclap stun |",
);
p(
  "| Escape | `the_9_12_from_hellstromme` | Moving train | Leaving a teammate behind at the wrong second |",
);
p("");
p("Each wave's special rule maps to a UEFN device:");
p("- **Holy Ground / Ghost-rock vein** → Volume Device + VFX prefab");
p("- **Zero Visibility** → Fog device + sight-limit zone");
p("- **Electric Air** → Damage Volume with random trigger");
p("- **Moving Train** → Mover device + hold-zone timer");
p("");

// --- Programmatic ingestion hint ----------------------------------------
p("---");
p("");
p("## How to consume this programmatically");
p("");
p("### Browser (tactical-combat.html)");
p("```js");
p("fetch('data/haunt_spec.json').then(r => r.json()).then(spec => {");
p("  const haunt = spec.haunts.find(h => h.id === 'cold_mine');");
p("  const roster = haunt.roster_by_tier['3'];");
p(
  "  // roster: [{ enemy_id: 'wendigo', count: 1 }, { enemy_id: 'wraith', count: 3 }]",
);
p("  const wendigo = spec.bestiary[roster[0].enemy_id];");
p("  spawnEnemy(wendigo, { x: 10, y: 5 });");
p("});");
p("```");
p("");
p("### UEFN / Verse");
p("```verse");
p("# At build time, haunt_spec.json is baked into a Verse class table.");
p(
  "# At runtime, look up the wave by id, iterate roster, spawn prefab per enemy_id.",
);
p('wave_spec := WaveSpec{HauntId := "drowned_preacher", Tier := 3}');
p("for (enemy : GetRoster(wave_spec)):");
p("    SpawnEnemy(GetBestiaryEntry(enemy.EnemyId), SpawnPoint)");
p("```");
p("");
p("### LLM planner (Claude)");
p(
  "Load `data/haunt_spec.json` into the prompt context. Claude can then compose new encounters by id-referencing existing enemies + locations + rules instead of inventing lore mid-stream.",
);
p("");

// --- Footer --------------------------------------------------------------
p("---");
p("");
p(`*Generated ${spec.generated} from ${spec.source} v${spec.version}.*`);
p("");

const outPath = path.join(__dirname, "..", "docs", "HAUNT_WAVE_CATALOG.md");
fs.writeFileSync(outPath, out.join("\n"));
console.log(`✓ wrote ${outPath} (${out.length} lines)`);
