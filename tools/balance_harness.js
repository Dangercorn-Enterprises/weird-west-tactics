#!/usr/bin/env node
// =============================================================================
// DUSTFALL — BALANCE HARNESS  (DEV-ONLY; lives OUTSIDE src/, never shipped)
//
// A headless, deterministic simulator that mirrors the EXACT combat math of
// the CANONICAL engine — godot/scripts/combat_core.gd (the Godot 4.7 HD-2D
// port, incl. Positioning v1 2026-07-09: LOS, banded-roll cover, high ground,
// destructible cover) — so we can measure encounter difficulty quantitatively
// (win-rate / turns / TTK / player deaths) headlessly.
//
// Fidelity strategy:
//   - Unit DATA (archetypes/weapons/pregens/enemy catalog) is required straight
//     from the real src/data.js — single source of truth, no copy.
//   - Combat MATH is a line-mirror of combat_core.gd; tools/parity_check.js
//     proves both engines produce the same win rates (±4 pts / 2000 runs).
//     Keep this file in sync when combat_core.gd changes, and re-run parity.
//   - HISTORY: this harness originally mirrored the web build
//     (src/scene_battle.js). Since the Godot port became the product, the web
//     build is the legacy PRE-Positioning-v1 reference and no longer matches.
//
// Usage:
//   node tools/balance_harness.js [runsPerEncounter]   (default 2000)
//   node tools/balance_harness.js 5000 --seed 12345
//   node tools/balance_harness.js --json               (machine-readable output)
// =============================================================================
"use strict";
const path = require("path");
const {
  ARCHETYPES,
  PREGEN,
  ENEMY_CATALOG,
  WEAPONS,
  ARMOR,
  WEAPON_MODS,
} = require(path.join(__dirname, "..", "src", "data.js"));

// ---- seedable RNG (mulberry32) so runs are reproducible ---------------------
function mulberry32(a) {
  return function () {
    a |= 0;
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
let RNG = Math.random;
let FAVOR = 1; // divine favor per unit's god (New Game seeds 1); --favor N to vary
let SCALE = true; // party-size encounter scaling (Phase 1d); --noscale to disable
const rnd = () => RNG();
const randint = (lo, hi) => lo + Math.floor(rnd() * (hi - lo + 1)); // inclusive
const chance = (pct) => rnd() * 100 < pct;

// ---- grid (mirror of scene_battle.js buildGrid, lines ~189-223) -------------
const COLS = 10,
  ROWS = 10;
const SPAWNS = [
  [8, 8],
  [9, 6],
  [8, 2],
  [9, 3],
  [7, 9],
  [9, 8],
  [8, 5],
];
const LIGHT_COVER_HP = 3; // absorbed would-be-hits before light cover is gone
const HUNKER_BONUS = 0.2; // hunker adds to cover bonus (was a flat -20 to-hit)
function buildGrid() {
  const grid = [];
  for (let r = 0; r < ROWS; r++) {
    grid.push([]);
    // cover: current bonus (0..0.4). cover0: original. chp: durability
    // (-1 = heavy/bullet-immune; >0 = light, decays). heavy: material flag.
    for (let q = 0; q < COLS; q++)
      grid[r].push({ h: 0, cover: 0, cover0: 0, chp: 0, heavy: false });
  }
  const set = (q, r, o) => Object.assign(grid[r][q], o);
  [
    [3, 2],
    [6, 7],
    [2, 6],
    [7, 3],
  ].forEach(([q, r]) => set(q, r, { h: 1 }));
  [
    [4, 4],
    [5, 5],
  ].forEach(([q, r]) => set(q, r, { h: 2 }));
  // heavy cover (rock/wall): 0.4 bonus, bullet-immune (chp -1)
  [
    [2, 3],
    [7, 6],
    [4, 7],
    [5, 2],
    [1, 5],
    [8, 4],
  ].forEach(([q, r]) =>
    set(q, r, { cover: 0.4, cover0: 0.4, chp: -1, heavy: true }),
  );
  // light cover (wagon/table/cactus): 0.2 bonus, decays over ~3 absorbed hits
  [
    [3, 5],
    [6, 4],
    [2, 8],
    [7, 8],
    [4, 1],
    [5, 8],
  ].forEach(([q, r]) =>
    set(q, r, { cover: 0.2, cover0: 0.2, chp: LIGHT_COVER_HP, heavy: false }),
  );
  return grid;
}

// Bresenham supercover line between two tiles (exclusive of endpoints).
// Mirror of combat_core.gd _line_tiles.
function lineTiles(aq, ar, bq, br) {
  const tiles = [];
  const dq = Math.abs(bq - aq),
    dr = Math.abs(br - ar);
  const sq = aq < bq ? 1 : -1,
    sr = ar < br ? 1 : -1;
  let err = dq - dr,
    q = aq,
    r = ar;
  while (q !== bq || r !== br) {
    const e2 = 2 * err;
    if (e2 > -dr) {
      err -= dr;
      q += sq;
    }
    if (e2 < dq) {
      err += dq;
      r += sr;
    }
    if (q === bq && r === br) break;
    tiles.push([q, r]);
  }
  return tiles;
}

// Direct-fire line of sight: a full-height (h>=2) tile between shooter and
// target blocks the shot. High ground shooting DOWN sees over one intervening
// wall lower than the perch. Mirror of combat_core.gd has_los.
function hasLos(grid, att, def) {
  const attH = grid[att.r][att.q].h,
    defH = grid[def.r][def.q].h;
  for (const [q, r] of lineTiles(att.q, att.r, def.q, def.r)) {
    if (grid[r][q].h >= 2) {
      if (attH > defH && grid[r][q].h <= attH) continue;
      return false;
    }
  }
  return true;
}

// Effective cover bonus (0..0.6) the defender enjoys vs THIS attacker.
// High ground on the shooter halves it; a defender on high ground gets NONE
// (beacon — skylined); hunker adds; point-blank bypasses (v1 flank proxy).
// Mirror of combat_core.gd cover_bonus.
function coverBonus(grid, att, def) {
  if (grid[def.r][def.q].h >= 1)
    return def.status.hunker > 0 ? HUNKER_BONUS : 0; // beacon
  let cb = grid[def.r][def.q].cover || 0;
  if (dist(att, def) <= 1)
    cb = 0; // point-blank flank negates cover
  else if (grid[att.r][att.q].h > grid[def.r][def.q].h) cb *= 0.5; // shooting down over low cover — half, not erased (Njord fix)
  if (def.status.hunker > 0) cb += HUNKER_BONUS;
  return Math.min(cb, 0.6); // cap so hunker can't fully erase the hit band
}

// ---- ability name maps (mirror of partyToUnit) ------------------------------
const ABIL = {
  gunslinger: "Fan the Hammer",
  hexslinger: "Hex Bolt",
  tinkerer: "Ashfall Grenade",
  preacher: "Lay on Hands",
  lawdog: "Called Shot",
  drifter: "Aimed Shot",
};
const ABIL2 = {
  gunslinger: "Gut Shot",
  hexslinger: "Soul Drain",
  tinkerer: "Arc Shock",
  preacher: "Holy Smite",
  lawdog: "Pistol Whip",
  drifter: "Both Barrels",
};
const DIVINE = {
  gunslinger: "Coyote's Gambit",
  hexslinger: "Samedi's Embrace",
  tinkerer: "Vulcan's Forgefire",
  preacher: "Perun's Thunder",
  lawdog: "Iron Verdict",
  drifter: "Anansi's Trick",
};

function mkUnit(o) {
  o.maxHp = o.hp;
  o.alive = true;
  o.maxAp = 3 + Math.floor(o.quick / 4);
  o.ap = o.maxAp;
  o.jinx = 0;
  o.status = {
    burn: 0,
    bleed: 0,
    hex: 0,
    marked: 0,
    hunker: 0,
    stun: 0,
    conf: 0,
  };
  return o;
}
function partyToUnit(p, i) {
  const arch = ARCHETYPES.find((a) => a.id === p.archetype) || null;
  // Pass 5/6 mirror: equipped store gear overrides the archetype default
  const gw =
    p.gear && p.gear.weapon
      ? WEAPONS.find((x) => x.id === p.gear.weapon)
      : null;
  const ga =
    p.gear && p.gear.armor ? ARMOR.find((x) => x.id === p.gear.armor) : null;
  const w = gw
    ? { damage: gw.dmg, range: gw.range, accuracy: gw.accuracy }
    : arch && arch.weapons && arch.weapons[0]
      ? arch.weapons[0]
      : { damage: [4, 8], range: 5, accuracy: 72 };
  const s = p.stats || {};
  const vigor = s.vigor || 5,
    quick = s.quickness || 5,
    str = s.strength || 4,
    deft = s.deftness || 5;
  const u = mkUnit({
    id: p.uid || "p" + i,
    name: p.name || (arch ? arch.name : "Rider"),
    archetype: p.archetype,
    god: p.god || null, // sworn shrine god fuels this unit's divine
    side: "p",
    q: 1,
    r: [1, 4, 7, 2][i] || 1,
    hp: Math.max(1, 10 + vigor * 2 - (p.hpDamage || 0)), // mirror: wounds never spawn you dead
    str,
    quick,
    aim: w.accuracy + (deft - 5) * 2,
    rng: w.range,
    wmin: w.damage[0],
    wmax: w.damage[1],
    abilities: [ABIL[p.archetype], ABIL2[p.archetype]].filter(Boolean),
    divine: DIVINE[p.archetype] || null,
    divineFavor: FAVOR,
    wIC: !!(gw && gw.ignoreCover),
    armorDef: ga ? ga.def : 0,
  });
  if (ga && ga.speed) {
    u.maxAp = Math.max(2, u.maxAp + ga.speed);
    u.ap = u.maxAp;
  }
  // Pass 15 mirror: fitted Forge mod tunes the weapon
  const gm =
    p.gear && p.gear.mod ? WEAPON_MODS.find((x) => x.id === p.gear.mod) : null;
  if (gm && gm.effect) {
    if (gm.effect.accuracy) u.aim += gm.effect.accuracy;
    if (gm.effect.range) u.rng = Math.max(1, u.rng + gm.effect.range);
    if (gm.effect.wmin) u.wmin = Math.max(1, u.wmin + gm.effect.wmin);
    if (gm.effect.wmax) u.wmax = Math.max(u.wmin, u.wmax + gm.effect.wmax);
  }
  return u;
}
function enemyToUnit(spec, i) {
  const beh = spec.behavior || "";
  const u = mkUnit({
    id: "e" + i,
    archetype: spec.id,
    name: spec.name,
    side: "e",
    q: 8,
    r: 1,
    hp: spec.hp,
    str: spec.str,
    quick: spec.quick,
    // Pass 10 mirror: braced sentries shoot straighter
    aim: spec.aim + (beh === "sentry" ? 8 : 0),
    rng: spec.rng,
    wmin: spec.wmin,
    wmax: spec.wmax,
    hexer: beh === "hexer",
    blinker: beh === "teleport",
    bomber: beh === "bomber",
    slammer: beh === "tank",
    // Pass 10 mirror: behavior flags
    sentry: beh === "sentry",
    zealot: beh === "zealot",
    swarmer: beh === "swarm",
    coverer: beh === "cover",
    flanker: beh === "flank",
    tier: spec.tier,
    boss: spec.boss,
  });
  return u;
}

// ---- combat math (verbatim mirror of combat_core.gd) ------------------------
const dist = (a, b) => Math.abs(a.q - b.q) + Math.abs(a.r - b.r);
// Bare-target hit % — everything EXCEPT cover/hunker (those live in coverBonus).
// Unclamped so the banded roll can compute the "would-hit-bare" ceiling.
function baseHit(grid, att, def) {
  let c = att.aim;
  c += (grid[att.r][att.q].h - grid[def.r][def.q].h) * 10;
  c -= Math.max(0, dist(att, def) - att.rng) * 15;
  if (att.jinx) c -= 15;
  if (att.status && att.status.hex > 0) c -= 15; // hexed: attacker less accurate
  return c;
}
// Effective chance to hit the UNIT (through cover). Used by AI EV + previews.
function hitChance(grid, att, def, ignoreCover) {
  const base = baseHit(grid, att, def);
  const cb = ignoreCover ? 0 : coverBonus(grid, att, def);
  return Math.max(5, Math.min(95, Math.round(base - cb * 100)));
}
function rollDmg(att) {
  return randint(att.wmin, att.wmax) + Math.floor(att.str / 3);
}

// BFS movement reachability (mirror of reach(), lines ~267-299)
function reach(grid, units, u) {
  const occupied = (q, r) =>
    units.some((x) => x.alive && x !== u && x.q === q && x.r === r);
  const res = {},
    key = (q, r) => q + "," + r;
  res[key(u.q, u.r)] = 0;
  const fr = [[u.q, u.r, 0]];
  while (fr.length) {
    const [q, r, c] = fr.shift();
    [
      [1, 0],
      [-1, 0],
      [0, 1],
      [0, -1],
    ].forEach(([dq, dr]) => {
      const nq = q + dq,
        nr = r + dr;
      if (nq < 0 || nr < 0 || nq >= COLS || nr >= ROWS) return;
      const cell = grid[nr][nq];
      if (cell.h >= 2) return;
      if (occupied(nq, nr)) return;
      const step = 1 + (cell.h > grid[r][q].h ? 1 : 0);
      const nc = c + step;
      if (
        nc <= u.ap &&
        (res[key(nq, nr)] === undefined || nc < res[key(nq, nr)])
      ) {
        res[key(nq, nr)] = nc;
        fr.push([nq, nr, nc]);
      }
    });
  }
  delete res[key(u.q, u.r)];
  return res;
}

// ---- damage application + death + boss-phase (mirror of fire()/blast()) ------
function applyDamage(B, def, dmg) {
  def.hp -= dmg;
  if (def.hp <= 0) {
    def.alive = false;
    if (def.side === "e") B.kills++;
    else B.playerDeaths++;
  } else {
    checkBossPhase(B, def);
  }
}
function doFire(B, att, def, opts) {
  opts = opts || {};
  const ic = opts.ignoreCover || att.wIC;
  // Direct fire needs line of sight (h>=2 terrain blocks the shot). Abilities
  // can waive it via opts.no_los (e.g. supernatural / thrown effects).
  if (!opts.no_los && !hasLos(B.grid, att, def)) return false;
  // Banded single roll (BT cover model): one draw split into hit /
  // strikes-cover / miss. Mirror of combat_core.gd do_fire — RNG order is
  // 1 draw on miss/strike, 3 on hit (band roll, dmg, crit).
  const hitThru = hitChance(B.grid, att, def, ic);
  const bare = Math.max(5, Math.min(95, Math.round(baseHit(B.grid, att, def))));
  const r = rnd() * 100;
  if (r < hitThru) {
    // HIT UNIT — RNG order preserved: rollDmg() then crit chance().
    const baseDmg = rollDmg(att);
    const isCrit = chance(10); // flat 10% crit at 1.5x, both sides
    let dmg = Math.round(baseDmg * (opts.mult || 1) * (isCrit ? 1.5 : 1));
    if (def.status && def.status.marked > 0) dmg = Math.round(dmg * 1.3); // marked
    if (def.armorDef) dmg = Math.max(1, dmg - def.armorDef); // armor soaks
    applyDamage(B, def, dmg);
    if (opts.status && def.alive)
      def.status[opts.status] = Math.max(
        def.status[opts.status] || 0,
        opts.statusN || 2,
      );
    if (att.hexer && def.alive) def.status.hex = Math.max(def.status.hex, 2);
    return true;
  } else if (!ic && r < bare) {
    // STRIKES COVER — the would-have-hit-bare band. Cover eats the shot and
    // degrades (light only); pure misses never strip cover.
    strikeCover(B, def.q, def.r);
  }
  return false;
}

// Degrade cover on an absorbed hit. Heavy (chp<0) shrugs off small arms;
// light decays its bonus as durability drops. Mirror of strike_cover.
function strikeCover(B, q, r) {
  const cell = B.grid[r][q];
  if (cell.chp <= 0) return; // heavy/indestructible or already gone
  cell.chp -= 1;
  cell.cover = cell.cover0 * (cell.chp / LIGHT_COVER_HP);
  if (cell.chp <= 0) cell.cover = 0;
}
// ---- status ticking (mirror of tickStatus() in scene_battle.js) -------------
const STATUS_DOT = { burn: 3, bleed: 2 };
function tickStatus(B, u) {
  if (!u || !u.alive || !u.status) return;
  if (u.status.burn > 0) {
    applyDamage(B, u, STATUS_DOT.burn);
    u.status.burn--;
  }
  ["hex", "marked", "hunker"].forEach((k) => {
    if (u.status[k] > 0) u.status[k]--;
  });
}
function doBlast(B, center) {
  // dynamite/AoE: chebyshev<=1, 4-7 dmg (mirror of do_blast)
  const caught = B.units.filter(
    (u) =>
      u.alive && Math.abs(u.q - center.q) <= 1 && Math.abs(u.r - center.r) <= 1,
  );
  caught.forEach((u) => {
    let dmg = randint(4, 7);
    if (u.armorDef) dmg = Math.max(1, dmg - u.armorDef); // armor soaks
    applyDamage(B, u, dmg);
  });
  // Explosives are the answer to cover: delete light in the radius, crack heavy.
  for (let dr = -1; dr <= 1; dr++)
    for (let dq = -1; dq <= 1; dq++) {
      const q = center.q + dq,
        r = center.r + dr;
      if (q < 0 || r < 0 || q >= COLS || r >= ROWS) continue;
      const cell = B.grid[r][q];
      if (!(cell.cover > 0)) continue;
      if (cell.heavy) {
        // crack heavy down a tier rather than vaporize it
        cell.cover = Math.max(0, cell.cover - 0.2);
        if (cell.cover <= 0) cell.heavy = false;
      } else {
        cell.cover = 0;
        cell.chp = 0;
      }
    }
}
function triggerBossPhase(B, b) {
  // mirror of triggerBossPhase(), lines ~483-521
  b.enraged = true;
  b.str += 3;
  b.aim += 12;
  b.wmax += 4;
  b.quick += 2;
  b.hp = Math.min(b.maxHp, b.hp + Math.round(b.maxHp * 0.25));
  const tmpl = ENEMY_CATALOG.find((e) => e.id === "walkin_dead");
  if (tmpl) {
    const taken = new Set(
      B.units.filter((u) => u.alive).map((u) => u.q + "," + u.r),
    );
    let added = 0;
    for (const [q, r] of SPAWNS) {
      if (added >= 2) break;
      if (taken.has(q + "," + r)) continue;
      const m = enemyToUnit(tmpl, 90 + added);
      m.name = "Risen Dead";
      m.q = q;
      m.r = r;
      B.enemies.push(m);
      B.units.push(m);
      taken.add(q + "," + r);
      added++;
    }
  }
}
function checkBossPhase(B, u) {
  if (u && u.boss && u.alive && !u.enraged && u.hp <= u.maxHp / 2)
    triggerBossPhase(B, u);
}

// ---- movement helper: step toward target along BFS-reachable tiles ----------
function moveToward(B, u, tgt) {
  const rc = reach(B.grid, B.units, u);
  // Pass 10 mirror: cover appetite varies by temperament (players keep weight 1)
  const coverW =
    u.side === "e" ? (u.coverer ? 2.5 : u.berserk || u.swarmer ? 0 : 1) : 1;
  // closer to the target is better; cover breaks ties (units seek cover)
  let best = null,
    bestScore = dist(u, tgt) * 2 - coverW * (B.grid[u.r][u.q].cover || 0);
  Object.keys(rc).forEach((k) => {
    const [q, r] = k.split(",").map(Number);
    const d = Math.abs(q - tgt.q) + Math.abs(r - tgt.r);
    const score = d * 2 - coverW * (B.grid[r][q].cover || 0);
    if (score < bestScore) {
      bestScore = score;
      best = [q, r];
    }
  });
  if (best) {
    u.ap -= rc[best[0] + "," + best[1]];
    u.q = best[0];
    u.r = best[1];
    if (u.status && u.status.bleed > 0) {
      applyDamage(B, u, STATUS_DOT.bleed); // bleed ticks on move
      u.status.bleed--;
    }
    return true;
  }
  return false;
}

// ---- ENEMY phase AI (mirror of enemyTurn(), lines ~527-611) -----------------
function enemyPhase(B) {
  const queue = B.enemies
    .filter((e) => e.alive)
    .sort((a, b) => (b.quick || 0) - (a.quick || 0));
  for (const e of queue) {
    if (!e.alive) continue;
    e.ap = e.maxAp;
    tickStatus(B, e); // burn/decrements at the start of this enemy's turn
    if (!e.alive) continue;
    // Pass 11 mirror: Perun's stun costs the whole activation
    if ((e.status.stun || 0) > 0) {
      e.status.stun--;
      continue;
    }
    let guard = 0;
    while (guard++ < 12) {
      const alive = B.players.filter((p) => p.alive);
      if (!alive.length) return;
      // Pass 11 mirror: Anansi's confusion — lash out at the nearest unit
      if ((e.status.conf || 0) > 0 && e.ap >= 2) {
        e.status.conf--;
        const near = B.units
          .filter((u) => u.alive && u !== e)
          .sort((a, b) => dist(e, a) - dist(e, b))[0];
        if (near && dist(e, near) <= e.rng + 1) {
          e.ap -= 2;
          doFire(B, e, near);
          continue;
        }
      }
      // Pass 10 mirror: zealots berserk once bloodied
      if (e.zealot && !e.berserk && e.hp <= e.maxHp / 2) {
        e.berserk = true;
        e.aim += 10;
        e.wmax += 2;
      }
      // Pass 10 mirror: behavior-driven target selection
      let tgt;
      if (e.flanker) {
        tgt = alive.slice().sort((a, b) => a.hp - b.hp)[0];
      } else if (e.swarmer) {
        tgt = alive.slice().sort((a, b) => dist(e, a) - dist(e, b))[0];
      } else {
        const inRng = alive.filter((p) => dist(e, p) <= e.rng + 1);
        // focus the weakest target in range; otherwise approach the nearest
        tgt = inRng.length
          ? inRng.slice().sort((a, b) => a.hp - b.hp)[0]
          : alive.slice().sort((a, b) => dist(e, a) - dist(e, b))[0];
      }
      if (!tgt) break;
      // Pass 10 mirror: sentries never chase
      if (e.sentry && dist(e, tgt) > e.rng + 1) break;
      if (dist(e, tgt) <= e.rng + 1 && e.ap >= 2) {
        const cluster = alive.filter(
          (p) => Math.abs(p.q - tgt.q) <= 1 && Math.abs(p.r - tgt.r) <= 1,
        ).length;
        const isBlast = e.bomber || (e.slammer && cluster >= 2);
        // Direct fire needs LOS; blasts lob over terrain. No clear shot ->
        // fall through to reposition instead of wasting the turn on a wall.
        if (isBlast || hasLos(B.grid, e, tgt)) {
          e.ap -= 2;
          if (isBlast) doBlast(B, tgt);
          else doFire(B, e, tgt);
          if (!B.players.some((p) => p.alive)) return;
          continue;
        }
      }
      if (e.blinker && e.ap >= 1 && dist(e, tgt) > e.rng) {
        const spots = [];
        for (let r = 0; r < ROWS; r++)
          for (let q = 0; q < COLS; q++) {
            if (B.grid[r][q].h >= 2) continue;
            if (B.units.some((x) => x.alive && x.q === q && x.r === r))
              continue;
            const d = Math.abs(q - tgt.q) + Math.abs(r - tgt.r);
            if (d >= 1 && d <= e.rng) spots.push([q, r]);
          }
        if (spots.length) {
          const s = spots[Math.floor(rnd() * spots.length)];
          e.q = s[0];
          e.r = s[1];
          e.ap -= 1;
          continue;
        }
      }
      if (e.ap > 0 && moveToward(B, e, tgt)) continue;
      break;
    }
  }
}

// ---- player ability model (mirror of doAbility(), scene_battle.js ~738-854) --
// atk = single hit at mult; multi = N shots at aimMod; heal; blast≈single approx.
const ABIL_FX = {
  "Fan the Hammer": { cost: 3, kind: "multi", shots: 3, aimMod: -10 },
  "Gut Shot": { cost: 2, kind: "atk", mult: 1.8, status: "bleed", statusN: 3 },
  "Both Barrels": {
    cost: 2,
    kind: "atk",
    mult: 1.8,
    status: "bleed",
    statusN: 3,
  },
  "Pistol Whip": { cost: 2, kind: "atk", mult: 1.8 },
  "Holy Smite": { cost: 2, kind: "atk", mult: 1.6 },
  "Arc Shock": { cost: 2, kind: "atk", mult: 1.4, ic: true },
  "Hex Bolt": { cost: 2, kind: "atk", ic: true, status: "hex", statusN: 2 },
  "Called Shot": {
    cost: 3,
    kind: "atk",
    guaranteed: true,
    status: "marked",
    statusN: 2,
  },
  "Aimed Shot": { cost: 2, kind: "atk", mult: 1.5 },
  "Ashfall Grenade": { cost: 2, kind: "blast" },
  "Lay on Hands": { cost: 2, kind: "heal", any: true },
  "Soul Drain": { cost: 2, kind: "heal", self: true },
};
// single-target divines = aim 999 (→95%), ignore cover, 2.5x; blast divines = 2 casts
const DIVINE_BLAST = new Set(["Vulcan's Forgefire", "Perun's Thunder"]);

const avgRoll = (u, mult) =>
  ((u.wmin + u.wmax) / 2 + Math.floor(u.str / 3)) * (mult || 1);
function expAtkDmg(grid, att, def, fx) {
  // No line of sight -> no shot: EV 0 so the policy never fires through a
  // wall. Only no_los effects are exempt (mirror of _exp_atk_dmg).
  if (!fx.no_los && !hasLos(grid, att, def)) return 0;
  const saved = att.aim;
  if (fx.aimMod) att.aim += fx.aimMod;
  const ch = fx.guaranteed ? 95 : hitChance(grid, att, def, fx.ic);
  att.aim = saved;
  return (((fx.shots || 1) * ch) / 100) * avgRoll(att, fx.mult);
}
const isHealer = (p) =>
  (p.abilities || []).some((a) => a === "Lay on Hands" || a === "Soul Drain");
function execAtk(B, p, def, fx) {
  const st = { status: fx.status, statusN: fx.statusN };
  if (fx.kind === "multi") {
    const sv = p.aim;
    p.aim += fx.aimMod || 0;
    for (let i = 0; i < fx.shots && def.alive; i++) doFire(B, p, def, st);
    p.aim = sv;
  } else if (fx.guaranteed) {
    const sv = p.aim;
    p.aim = 999;
    doFire(B, p, def, st);
    p.aim = sv;
  } else if (fx.kind === "blast") {
    doBlast(B, def);
  } else {
    doFire(B, p, def, {
      mult: fx.mult,
      ignoreCover: fx.ic,
      status: fx.status,
      statusN: fx.statusN,
    });
  }
}

// ---- PLAYER phase AI ---------------------------------------------------------
// Two policies. BASIC (--basic) = basic attacks only, a conservative floor.
// ABILITIES (default) = a competent player: heal when hurt, pop the once-per-fight
// divine on the biggest threat, otherwise spend AP on the best damage-per-AP
// action available (Gut Shot / Fan the Hammer / Called Shot / basic). Real play
// sits between the two. Both validated against the live combat math.
function playerPhaseBasic(B) {
  const order = B.players
    .filter((p) => p.alive)
    .sort((a, b) => (b.quick || 0) - (a.quick || 0));
  for (const p of order) {
    if (!p.alive) continue;
    p.ap = p.maxAp;
    tickStatus(B, p);
    if (!p.alive) continue;
    let guard = 0;
    while (guard++ < 12) {
      const inRange = B.enemies
        .filter((e) => e.alive && dist(p, e) <= p.rng + 1)
        .sort((a, b) => a.hp - b.hp);
      if (inRange.length && p.ap >= 2) {
        p.ap -= 2;
        doFire(B, p, inRange[0]);
        if (!B.enemies.some((e) => e.alive)) return;
        continue;
      }
      const nearest = B.enemies
        .filter((e) => e.alive)
        .sort((a, b) => dist(p, a) - dist(p, b))[0];
      if (nearest && p.ap > 0 && moveToward(B, p, nearest)) continue;
      break;
    }
  }
  B.players.forEach((p) => (p.jinx = 0));
}
function playerPhaseAbilities(B) {
  const order = B.players
    .filter((p) => p.alive)
    .sort((a, b) => (b.quick || 0) - (a.quick || 0));
  for (const p of order) {
    if (!p.alive) continue;
    p.ap = p.maxAp;
    tickStatus(B, p);
    if (!p.alive) continue;
    let guard = 0;
    while (guard++ < 12 && p.ap >= 2) {
      if (!B.enemies.some((e) => e.alive)) break;
      // 1) heal a badly hurt ally/self (mirror chooseAbility heal targeting)
      if (isHealer(p)) {
        const self = (p.abilities || []).includes("Soul Drain");
        const pool = self ? [p] : B.players.filter((a) => a.alive);
        const hurt = pool
          .filter((a) => a.hp / a.maxHp < 0.4)
          .sort((a, b) => a.hp / a.maxHp - b.hp / b.maxHp)[0];
        if (hurt) {
          hurt.hp = Math.min(hurt.maxHp, hurt.hp + randint(6, 10));
          p.ap -= 2;
          continue;
        }
      }
      // 2) move into range if nothing is in range
      const inRange = B.enemies.filter(
        (e) => e.alive && dist(p, e) <= p.rng + 1,
      );
      if (!inRange.length) {
        const nearest = B.enemies
          .filter((e) => e.alive)
          .sort((a, b) => dist(p, a) - dist(p, b))[0];
        if (p.ap > 0 && moveToward(B, p, nearest)) continue;
        break;
      }
      // 3) divine: pop once per fight on the biggest in-range threat.
      // Phase 1b: gated by favor — needs >=1 (consumes 1), empowered at >=3.
      if (p.divine && !p.divineUsed && (p.divineFavor || 0) >= 1) {
        const threat = inRange.slice().sort((a, b) => b.hp - a.hp)[0];
        if (threat.boss || threat.hp >= 18) {
          // save the ult for real threats, not trash
          const emp = (p.divineFavor || 0) >= 3;
          p.divineFavor = Math.max(0, (p.divineFavor || 0) - 1);
          p.divineUsed = true;
          if (DIVINE_BLAST.has(p.divine)) {
            doBlast(B, threat);
            doBlast(B, threat);
            if (emp) doBlast(B, threat);
            // Pass 11 mirror: Vulcan burns, Perun stuns the survivors
            const rk = p.divine === "Vulcan's Forgefire" ? "burn" : "stun";
            B.enemies
              .filter(
                (x) =>
                  x.alive &&
                  Math.abs(x.q - threat.q) <= 1 &&
                  Math.abs(x.r - threat.r) <= 1,
              )
              .forEach((x) => {
                x.status[rk] = Math.max(
                  x.status[rk] || 0,
                  rk === "burn" ? 2 : 1,
                );
              });
          } else {
            const sv = p.aim;
            p.aim = 999;
            doFire(B, p, threat, {
              ignoreCover: true,
              mult: emp ? 3.5 : 2.5,
              status: emp ? "marked" : null,
              statusN: 2,
            });
            p.aim = sv;
            // Pass 11 mirror: single-target divine riders
            if (p.divine === "Samedi's Embrace")
              p.hp = Math.min(p.maxHp, p.hp + (emp ? 9 : 6));
            else if (p.divine === "Coyote's Gambit")
              p.status.hunker = Math.max(p.status.hunker, 2);
            else if (p.divine === "Iron Verdict" && threat.alive)
              threat.status.marked = Math.max(threat.status.marked, 2);
            else if (p.divine === "Anansi's Trick" && threat.alive)
              threat.status.conf = Math.max(threat.status.conf || 0, 1);
          }
          p.ap = 0; // divine ends the turn
          continue;
        }
      }
      // 4) best damage-per-AP action on the lowest-HP focus target
      const focus = inRange.slice().sort((a, b) => a.hp - b.hp)[0];
      const opts = [{ fx: { cost: 2, kind: "atk", mult: 1 } }];
      (p.abilities || []).forEach((name) => {
        const fx = ABIL_FX[name];
        if (fx && fx.kind !== "heal" && fx.cost <= p.ap) opts.push({ fx });
      });
      const aff = opts.filter((o) => o.fx.cost <= p.ap);
      aff.sort(
        (a, b) =>
          expAtkDmg(B.grid, p, focus, b.fx) / b.fx.cost -
          expAtkDmg(B.grid, p, focus, a.fx) / a.fx.cost,
      );
      const choice = aff[0];
      execAtk(B, p, focus, choice.fx);
      p.ap -= choice.fx.cost;
      if (!B.enemies.some((e) => e.alive)) return;
    }
  }
  B.players.forEach((p) => (p.jinx = 0)); // jinx clears at end of player phase (~691)
}
let PLAYER_POLICY = playerPhaseAbilities;

// ---- one battle -------------------------------------------------------------
function runBattle(partySpecs, enemySpecs, maxRounds) {
  const grid = buildGrid();
  const players = partySpecs.slice(0, 4).map(partyToUnit);
  const enemies = enemySpecs.map((spec, i) => {
    const u = enemyToUnit(spec, i);
    const [q, r] = SPAWNS[i] || SPAWNS[i % SPAWNS.length];
    u.q = q;
    u.r = r;
    return u;
  });
  const B = {
    grid,
    players,
    enemies,
    units: [...players, ...enemies],
    kills: 0,
    playerDeaths: 0,
  };
  let round = 0;
  let enemyDeathRound = null;
  for (round = 1; round <= maxRounds; round++) {
    PLAYER_POLICY(B);
    if (!B.enemies.some((e) => e.alive)) {
      enemyDeathRound = round;
      break;
    }
    enemyPhase(B);
    if (!B.players.some((p) => p.alive)) break;
  }
  const win = B.players.some((p) => p.alive) && !B.enemies.some((e) => e.alive);
  return {
    win,
    rounds: Math.min(round, maxRounds),
    timedOut: round > maxRounds,
    playerDeaths: B.playerDeaths,
    survivors: B.players.filter((p) => p.alive).length,
    enemyDeathRound,
  };
}

// Phase 1d: normalize encounter difficulty to party size so there are no brick
// walls. Designed around a 3-strong posse; smaller parties face weaker foes,
// larger parties tougher ones. Mirror of DF.scaleEncounter in scene_battle.js.
function scaleEncounter(specs, partySize) {
  // balance 2026-07-01: 4-party clamps 1.35/1.2 (mirror of DF.scaleEncounter)
  const hpF = Math.max(0.6, Math.min(1.35, 0.6 + 0.25 * (partySize - 2)));
  const dmgF = Math.max(0.8, Math.min(1.2, 0.8 + 0.1 * (partySize - 2)));
  if (hpF === 1 && dmgF === 1) return specs;
  return specs.map((s) =>
    Object.assign({}, s, {
      hp: Math.max(4, Math.round(s.hp * hpF)),
      wmin: Math.max(1, Math.round(s.wmin * dmgF)),
      wmax: Math.max(2, Math.round(s.wmax * dmgF)),
    }),
  );
}

// ---- aggregate over N runs --------------------------------------------------
function evalEncounter(name, party, enemyIds, runs) {
  const raw = enemyIds
    .map((id) => ENEMY_CATALOG.find((e) => e.id === id))
    .filter(Boolean);
  const enemySpecs = SCALE ? scaleEncounter(raw, party.length) : raw;
  let wins = 0,
    totRounds = 0,
    totDeaths = 0,
    totSurv = 0,
    totTTK = 0,
    ttkN = 0,
    timeouts = 0;
  for (let i = 0; i < runs; i++) {
    const res = runBattle(party, enemySpecs, 60);
    if (res.win) {
      wins++;
      if (res.enemyDeathRound) {
        totTTK += res.enemyDeathRound;
        ttkN++;
      }
    }
    if (res.timedOut) timeouts++;
    totRounds += res.rounds;
    totDeaths += res.playerDeaths;
    totSurv += res.survivors;
  }
  return {
    name,
    enemies: enemyIds.join("+"),
    n: runs,
    winRate: wins / runs,
    avgRounds: totRounds / runs,
    avgDeaths: totDeaths / runs,
    avgSurvivors: totSurv / runs,
    avgTTK: ttkN ? totTTK / ttkN : null,
    timeoutRate: timeouts / runs,
  };
}

// ---- parties ----------------------------------------------------------------
function mkParty(ids) {
  return ids.map((aid, i) => ({
    uid: "p" + i,
    archetype: aid,
    name: PREGEN[aid] ? PREGEN[aid].name : aid,
    stats: PREGEN[aid] ? Object.assign({}, PREGEN[aid].stats) : {},
    hpDamage: 0,
  }));
}
const starterParty = () => mkParty(["gunslinger", "hexslinger"]);
const fullParty = () =>
  mkParty(["gunslinger", "hexslinger", "preacher", "lawdog"]);

// ---- the encounters the game ACTUALLY launches (from scene_*.js) ------------
const ENCOUNTERS = [
  [
    "Quick Skirmish (default)",
    "starter",
    ["walkin_dead", "coyote_beast", "forge_sentry", "dust_devil"],
  ],
  [
    "Act 1 · Revenant Vanguard",
    "starter",
    ["revenant_gun", "walkin_dead", "dynamite_bandit", "dynamite_bandit"],
  ],
  [
    "Act 1 · The Deacon (boss)",
    "starter",
    ["the_deacon", "walkin_dead", "walkin_dead", "coyote_beast"],
  ],
  [
    "Reckoning · Iron Foreman",
    "starter",
    ["iron_foreman", "forge_sentry", "forge_sentry"],
  ],
  [
    "Reckoning · The Weaver",
    "starter",
    ["the_weaver", "dust_witch", "dust_witch"],
  ],
  [
    "Reckoning · Hollow Man",
    "starter",
    ["hollow_man", "dust_devil", "dust_devil"],
  ],
  [
    "Ambush · trail T1",
    "starter",
    ["walkin_dead", "coyote_beast", "rattlesnake"],
  ],
  [
    "Ambush · wilderness T2",
    "starter",
    ["revenant_gun", "dynamite_bandit", "ashfall_golem"],
  ],
  [
    "Act 1 · The Deacon (4-party)",
    "full",
    ["the_deacon", "walkin_dead", "walkin_dead", "coyote_beast"],
  ],
  [
    "Reckoning · Iron Foreman (4-party)",
    "full",
    ["iron_foreman", "ashfall_golem", "forge_sentry"],
  ],
  // ---- campaign Act 2 / Act 3 set-pieces (reached with a grown party) ----
  [
    "Act 2 · Forgeworks Vanguard",
    "full",
    ["forge_sentry", "forge_sentry", "ashfall_golem", "dynamite_bandit"],
  ],
  [
    "Act 2 · Iron Foreman",
    "full",
    ["iron_foreman", "ashfall_golem", "forge_sentry"],
  ],
  [
    "Act 3 · Weaver Heralds",
    "full",
    ["the_weaver", "dust_witch", "revenant_gun"],
  ],
  [
    "Act 3 · Hollow Man (finale)",
    "full",
    ["hollow_man", "coyotes_shadow", "dust_devil"],
  ],
];

// ---- main -------------------------------------------------------------------
function main() {
  const args = process.argv.slice(2);
  const jsonOut = args.includes("--json");
  const seedIdx = args.indexOf("--seed");
  const seed = seedIdx >= 0 ? parseInt(args[seedIdx + 1], 10) : 1337;
  const runsArg = args.find((a) => /^\d+$/.test(a));
  const runs = runsArg ? parseInt(runsArg, 10) : 2000;
  const basic = args.includes("--basic");
  PLAYER_POLICY = basic ? playerPhaseBasic : playerPhaseAbilities;
  const favorIdx = args.indexOf("--favor");
  if (favorIdx >= 0) FAVOR = parseInt(args[favorIdx + 1], 10) || 0;
  if (args.includes("--noscale")) SCALE = false;
  RNG = mulberry32(seed);

  const parties = { starter: starterParty(), full: fullParty() };
  const results = ENCOUNTERS.map(([name, partyKey, ids]) =>
    evalEncounter(name, parties[partyKey], ids, runs),
  );

  if (jsonOut) {
    console.log(JSON.stringify({ seed, runs, results }, null, 2));
    return;
  }

  const pct = (x) => (x * 100).toFixed(1).padStart(5) + "%";
  const num = (x, d = 1) => (x == null ? "  -  " : x.toFixed(d).padStart(5));
  console.log(
    `\nDUSTFALL balance harness — ${runs} runs/encounter, seed ${seed}`,
  );
  console.log(
    basic
      ? "  (policy = BASIC ATTACKS ONLY → conservative floor)\n"
      : "  (policy = ABILITY-AWARE: heals + divines + best dmg/AP → competent player; --basic for the floor)\n",
  );
  console.log(
    "ENCOUNTER".padEnd(34) +
      "WIN%".padStart(7) +
      "ROUNDS".padStart(8) +
      "TTK".padStart(7) +
      "DEATHS".padStart(8) +
      "SURV".padStart(7) +
      "T/O%".padStart(7),
  );
  console.log("-".repeat(78));
  for (const r of results) {
    console.log(
      r.name.padEnd(34) +
        pct(r.winRate).padStart(7) +
        num(r.avgRounds).padStart(8) +
        num(r.avgTTK).padStart(7) +
        num(r.avgDeaths, 2).padStart(8) +
        num(r.avgSurvivors, 2).padStart(7) +
        pct(r.timeoutRate).padStart(7),
    );
  }
  console.log("-".repeat(78));
  console.log(
    "\nTarget bands: story 70-85% · ambush 80-90% · boss 45-65% (real play, with abilities, sits above the floor)\n",
  );
}

if (require.main === module) main();

module.exports = {
  setSeed: (s) => {
    RNG = mulberry32(s);
  },
  runBattle,
  evalEncounter,
  hitChance,
  rollDmg,
  buildGrid,
  starterParty,
  fullParty,
  partyToUnit,
  enemyToUnit,
};
