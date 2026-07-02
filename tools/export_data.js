#!/usr/bin/env node
// =============================================================================
// DUSTFALL — DATA EXPORTER (DEV-ONLY)
// src/data.js + src/sprites.js are the single source of truth for game design.
// This ships them as JSON for the Godot port (godot/data/*.json), so the web
// build, the Node balance harness, and the Godot engine all read one truth.
// Run: node tools/export_data.js   (re-run after any data.js/sprites.js change)
// =============================================================================
"use strict";
const fs = require("fs");
const path = require("path");
const ROOT = path.join(__dirname, "..");
const D = require(path.join(ROOT, "src", "data.js"));
const S = require(path.join(ROOT, "src", "sprites.js"));
const W = require(path.join(ROOT, "src", "worldmap_data.js"));

const out = path.join(ROOT, "godot", "data");
fs.mkdirSync(out, { recursive: true });

fs.writeFileSync(
  path.join(out, "design.json"),
  JSON.stringify(
    {
      archetypes: D.ARCHETYPES,
      stats: D.STATS,
      pregen: D.PREGEN,
      gods: D.GODS,
      enemies: D.ENEMY_CATALOG,
      weapons: D.WEAPONS,
      armor: D.ARMOR,
      consumables: D.CONSUMABLES,
      weapon_mods: D.WEAPON_MODS,
      mounts: D.MOUNTS,
      biomes: D.BIOMES,
      world_nodes: W.WORLD_NODES,
      world_edges: W.WORLD_EDGES,
    },
    null,
    2,
  ),
);
fs.writeFileSync(
  path.join(out, "sprites.json"),
  JSON.stringify({ palette: S.SPRITE_PAL, sprites: S.SPRITES }, null, 2),
);
console.log(
  "exported design.json (" +
    Object.keys(D.ENEMY_CATALOG).length +
    " enemies, " +
    Object.keys(D.BIOMES).length +
    " biomes) + sprites.json (" +
    Object.keys(S.SPRITES).length +
    " sprites)",
);
