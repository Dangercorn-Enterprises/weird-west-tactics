// =============================================
// DUSTFALL — BATTLE SCENE (the LOCKED iso/elevation/cover combat core)
// Ported from src/dustfall-arena.html (v0.3, verified). Combat math, AI, and
// rendering are preserved verbatim; only the lifecycle changed: encounter-driven,
// roster-built units, and a result callback instead of location.reload().
// Markup lives in game.html (#scene-battle); this file owns the logic.
// =============================================
(function () {
  "use strict";
  const DF = (window.DF = window.DF || {});

  const COLS = 10,
    ROWS = 10,
    TW = 64,
    TH = 32;
  const ORIGIN = { x: 450, y: 90 };
  const PAL = {
    amber: "#d4a843",
    blood: "#c0392b",
    teal: "#4ecdc4",
    parch: "#d4c5a9",
    rust: "#a0522d",
    ink: "#1a1209",
  };
  const SPAWNS = [
    [8, 8],
    [9, 6],
    [8, 2],
    [9, 3],
    [7, 9],
    [9, 8],
    [8, 5],
  ];

  let C,
    X,
    fit,
    built = false,
    active = false,
    onComplete = null;
  let grid,
    players,
    enemies,
    sel,
    turn,
    reachable,
    shake,
    particles,
    floaters,
    abilityMode,
    busy,
    kills,
    turnsTaken,
    ended;

  const $ = (id) => document.querySelector('[data-scene="battle"] #' + id);

  // ---- wire up the static markup from game.html (no innerHTML) ----
  function build() {
    const host = document.querySelector('[data-scene="battle"]');
    C = host.querySelector("#bc");
    X = C.getContext("2d");
    fit = DF.fitCanvas(C, 900, 620);
    C.addEventListener("mousemove", (e) => {
      const p = fit.toLocal(e.clientX, e.clientY);
      C.hoverTile = tileUnderMouse(p.x, p.y);
    });
    C.addEventListener("click", onCanvasClick);
    host.querySelector("#bendBtn").onclick = endPlayerTurn;
    host.querySelector("#babilityBtn").onclick = openAbilityMenu;
    const ib = host.querySelector("#bitemsBtn");
    if (ib) ib.onclick = openItemMenu;
    host.querySelector("#bbannerBtn").onclick = () => {
      if (onComplete) onComplete(lastResult);
    };
    built = true;
  }

  // ---- unit construction ----
  function mkUnit(o) {
    o.maxHp = o.hp;
    o.alive = true;
    o.downed = 0;
    o.flash = 0;
    o.maxAp = 3 + Math.floor(o.quick / 4);
    o.ap = o.maxAp;
    o.status = { burn: 0, bleed: 0, hex: 0, marked: 0, hunker: 0 }; // Phase 1a
    return o;
  }

  function partyToUnit(p, i) {
    const arch =
      typeof ARCHETYPES !== "undefined"
        ? ARCHETYPES.find((a) => a.id === p.archetype)
        : null;
    // Pass 5 (v1.1): an equipped store weapon overrides the archetype default.
    // Catalog WEAPONS use {dmg,...}; archetype weapons use {damage,...} — normalize.
    const gw =
      p.gear && p.gear.weapon && typeof WEAPONS !== "undefined"
        ? WEAPONS.find((x) => x.id === p.gear.weapon)
        : null;
    const w = gw
      ? { damage: gw.dmg, range: gw.range, accuracy: gw.accuracy }
      : arch && arch.weapons && arch.weapons[0]
        ? arch.weapons[0]
        : { damage: [4, 8], range: 5, accuracy: 72 };
    // Pass 6 (v1.1): armor = flat damage reduction; heavy plate costs speed.
    const ga =
      p.gear && p.gear.armor && typeof ARMOR !== "undefined"
        ? ARMOR.find((x) => x.id === p.gear.armor)
        : null;
    const s = p.stats || {};
    const vigor = s.vigor || 5,
      quick = s.quickness || 5,
      str = s.strength || 4,
      deft = s.deftness || 5;
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
    const primary = ABIL[p.archetype] || "Aimed Shot";
    const abilities = [primary, ABIL2[p.archetype]].filter(Boolean);
    const divine = DIVINE[p.archetype] || null;
    const u = mkUnit({
      id: p.uid || "p" + i,
      name: p.name || (arch ? arch.name : "Rider"),
      role: arch ? arch.name : "Rider",
      archetype: p.archetype, // needed for favor/god resolution (Phase 1b)
      god: p.god || null, // a unit sworn at a shrine fuels its divine from that god
      side: "p",
      q: 1,
      r: [1, 4, 7, 2][i] || 1,
      hp: Math.max(1, 10 + vigor * 2 - (p.hpDamage || 0)), // wounds never spawn you dead
      str,
      quick,
      aim: w.accuracy + (deft - 5) * 2,
      rng: w.range,
      wmin: w.damage[0],
      wmax: w.damage[1],
      color: archColor(p.archetype),
      ability: primary,
      abilities,
      divine,
      wIC: !!(gw && gw.ignoreCover), // Hex Focus etc: basic shots ignore cover
      armorDef: ga ? ga.def : 0,
      weaponName: gw ? gw.name : null,
      armorName: ga ? ga.name : null,
    });
    if (ga && ga.speed) {
      u.maxAp = Math.max(2, u.maxAp + ga.speed); // heavy plate slows you down
      u.ap = u.maxAp;
    }
    return u;
  }
  function archColor(id) {
    return (
      {
        gunslinger: "#e8c88a",
        hexslinger: "#b98ed4",
        tinkerer: "#caa86a",
        preacher: "#e8dcc8",
        lawdog: "#88aacc",
        drifter: "#c8a070",
      }[id] || "#d4c5a9"
    );
  }

  function enemyToUnit(spec, i) {
    const beh = spec.behavior || "";
    const u = mkUnit({
      id: "e" + i,
      archetype: spec.id,
      name: spec.name,
      role: spec.faction || "",
      side: "e",
      q: 8,
      r: 1,
      color: spec.color || "#c0392b",
      hp: spec.hp,
      str: spec.str,
      quick: spec.quick,
      // a braced emplacement shoots straighter than anything on the move
      aim: spec.aim + (beh === "sentry" ? 8 : 0),
      rng: spec.rng,
      wmin: spec.wmin,
      wmax: spec.wmax,
      hexer: beh === "hexer",
      blinker: beh === "teleport",
      bomber: beh === "bomber",
      slammer: beh === "tank", // golems slam for AoE when players cluster
      // Pass 10 (v1.1): the rest of the catalog behaviors, finally wired
      sentry: beh === "sentry", // emplacement — holds ground, never chases
      zealot: beh === "zealot", // berserks below half HP (+aim, +dmg, no cover)
      swarmer: beh === "swarm", // rushes the closest target
      coverer: beh === "cover", // weights cover heavily when moving
      flanker: beh === "flank", // hunts the weakest rider on the field
      tier: spec.tier,
      boss: spec.boss,
    });
    return u;
  }

  // ---- status effects (Phase 1a) -------------------------------------------
  // burn   = damage-over-time, ticks each of the unit's turns
  // bleed  = damage-over-time, ticks when the unit MOVES (punishes repositioning)
  // hex    = the afflicted unit's own attacks lose accuracy (-15)
  // marked = the afflicted unit takes +30% damage (rewards focus fire)
  // hunker = the afflicted unit is harder to hit (-20 to attackers) — a defensive buff
  const STATUS_META = {
    burn: { tag: "BRN", col: "#e8704f", dot: 3 },
    bleed: { tag: "BLD", col: "#c0392b", dot: 2 },
    hex: { tag: "HEX", col: "#9a6ab8" },
    marked: { tag: "MRK", col: "#d4a843" },
    hunker: { tag: "HNK", col: "#4ecdc4" },
  };

  // ---- per-ability AP costs (mirrored in tools/balance_harness.js ABIL_FX) ----
  const ABIL_COST = { "Fan the Hammer": 3, "Called Shot": 3, "Hunker Down": 1 };
  const abilCost = (name) => ABIL_COST[name] || 2;
  function applyStatus(u, key, dur) {
    if (!u || !u.alive || !u.status) return;
    u.status[key] = Math.max(u.status[key] || 0, dur); // refresh to longest duration
    const p = iso(u.q, u.r, grid[u.r][u.q].h);
    floaters.push({
      x: p.x,
      y: p.y - 52,
      t: STATUS_META[key].tag,
      life: 40,
      c: STATUS_META[key].col,
    });
  }
  function statusDamage(u, dmg, key) {
    if (!u || !u.alive) return;
    u.hp -= dmg;
    u.flash = 8;
    const p = iso(u.q, u.r, grid[u.r][u.q].h);
    floaters.push({
      x: p.x,
      y: p.y - 40,
      t: "-" + dmg,
      life: 36,
      c: STATUS_META[key].col,
    });
    if (u.hp <= 0) {
      u.alive = false;
      u.downed = 1;
      if (u.side === "e") kills++;
      log(u.name + " succumbs to " + key + ".");
    }
  }
  // tick burn + decrement timed statuses at the start of a unit's activation
  function tickStatus(u) {
    if (!u || !u.alive || !u.status) return;
    if (u.status.burn > 0) {
      statusDamage(u, STATUS_META.burn.dot, "burn");
      u.status.burn--;
    }
    ["hex", "marked", "hunker"].forEach((k) => {
      if (u.status[k] > 0) u.status[k]--;
    });
  }

  // ---- grid setup (Pass 9, v1.1): biome battle maps -------------------------
  // Every biome keeps a comparable tactical budget (~4-5 h1, 0-2 h2, ~6 hard
  // cover, ~6 soft cover) so the balance harness's canonical mesa map stays
  // representative. Spawn tiles (players q=1; SPAWNS) are never h2-blocked.
  const BIOMES = {
    mesa: {
      floors: ["#3a2c18", "#4a3820", "#5a4428"],
      h1: [
        [3, 2],
        [6, 7],
        [2, 6],
        [7, 3],
      ],
      h2: [
        [4, 4],
        [5, 5],
      ],
      hard: [
        [2, 3],
        [7, 6],
        [4, 7],
        [5, 2],
        [1, 5],
        [8, 4],
      ],
      soft: [
        [3, 5],
        [6, 4],
        [2, 8],
        [7, 8],
        [4, 1],
        [5, 8],
      ],
      hardDeco: "crate",
      softDeco: "cactus",
    },
    canyon: {
      floors: ["#42291a", "#553522", "#68422a"],
      h1: [
        [4, 1],
        [5, 2],
        [4, 8],
        [5, 7],
        [6, 6],
      ],
      h2: [
        [5, 4],
        [4, 5],
      ],
      hard: [
        [2, 4],
        [7, 5],
        [3, 3],
        [6, 8],
        [2, 7],
        [7, 2],
      ],
      soft: [
        [1, 3],
        [8, 6],
        [3, 8],
        [6, 1],
        [2, 5],
        [7, 7],
      ],
      hardDeco: "rock",
      softDeco: "cactus",
    },
    town: {
      floors: ["#3d3020", "#4d3d28", "#5d4a30"],
      h1: [
        [3, 3],
        [3, 4],
        [6, 5],
        [6, 6],
      ],
      h2: [
        [3, 7],
        [6, 2],
      ],
      hard: [
        [2, 5],
        [5, 4],
        [7, 7],
        [4, 6],
        [5, 1],
        [2, 2],
      ],
      soft: [
        [1, 7],
        [4, 3],
        [7, 4],
        [3, 8],
        [6, 8],
        [5, 6],
      ],
      hardDeco: "crate",
      softDeco: "barrel",
    },
    boneyard: {
      floors: ["#33302a", "#413d35", "#4f4a40"],
      h1: [
        [5, 5],
        [2, 3],
        [7, 6],
      ],
      h2: [[4, 3]],
      hard: [
        [3, 6],
        [6, 3],
        [2, 7],
        [7, 2],
        [5, 8],
        [4, 1],
      ],
      soft: [
        [2, 5],
        [7, 5],
        [4, 7],
        [5, 2],
        [3, 1],
        [6, 8],
      ],
      hardDeco: "grave",
      softDeco: "bone",
    },
    foundry: {
      floors: ["#2e2418", "#3e3020", "#544022"],
      h1: [
        [2, 2],
        [7, 7],
        [4, 5],
        [5, 4],
      ],
      h2: [
        [3, 6],
        [6, 3],
      ],
      hard: [
        [1, 4],
        [8, 6],
        [4, 2],
        [5, 7],
        [2, 8],
        [7, 1],
      ],
      soft: [
        [3, 3],
        [6, 6],
        [2, 6],
        [7, 4],
        [4, 8],
        [5, 1],
      ],
      hardDeco: "pipe",
      softDeco: "ember",
    },
    hollow: {
      floors: ["#20262a", "#2b3338", "#364046"],
      h1: [
        [4, 4],
        [5, 5],
        [3, 7],
        [6, 2],
      ],
      h2: [],
      hard: [
        [2, 4],
        [7, 5],
        [5, 2],
        [4, 7],
        [3, 3],
        [6, 8],
      ],
      soft: [
        [1, 6],
        [8, 3],
        [3, 2],
        [6, 7],
        [2, 8],
        [7, 8],
      ],
      hardDeco: "spire",
      softDeco: "wisp",
    },
  };
  let biome = BIOMES.mesa;
  function buildGrid(biomeId) {
    biome = BIOMES[biomeId] || BIOMES.mesa;
    grid = [];
    for (let r = 0; r < ROWS; r++) {
      grid.push([]);
      for (let q = 0; q < COLS; q++)
        grid[r].push({ h: 0, cover: 0, deco: null });
    }
    const set = (q, r, o) => Object.assign(grid[r][q], o);
    biome.h1.forEach(([q, r]) => set(q, r, { h: 1, deco: "mesa" }));
    biome.h2.forEach(([q, r]) => set(q, r, { h: 2, deco: "mesa" }));
    biome.hard.forEach(([q, r]) =>
      set(q, r, { cover: 0.4, deco: biome.hardDeco }),
    );
    biome.soft.forEach(([q, r]) =>
      set(q, r, { cover: 0.2, deco: biome.softDeco }),
    );
  }

  const all = () => [...players, ...enemies].filter((u) => u.alive);
  function unitAt(q, r) {
    return all().find((u) => u.q === q && u.r === r);
  }

  const logs = [];
  function log(m) {
    logs.push(m);
    if (logs.length > 7) logs.shift();
    const el = $("blog");
    if (!el) return;
    while (el.firstChild) el.removeChild(el.firstChild);
    logs.forEach((l) => {
      const d = document.createElement("div");
      d.textContent = l;
      el.appendChild(d);
    });
  }

  function iso(q, r, h = 0) {
    return {
      x: ORIGIN.x + ((q - r) * TW) / 2,
      y: ORIGIN.y + ((q + r) * TH) / 2 - h * 18,
    };
  }
  function tileUnderMouse(mx, my) {
    let best = null,
      bd = 1e9;
    for (let r = 0; r < ROWS; r++)
      for (let q = 0; q < COLS; q++) {
        const p = iso(q, r, grid[r][q].h);
        const dx = mx - p.x,
          dy = my - (p.y + TH / 2);
        const d = dx * dx * 0.5 + dy * dy * 2;
        if (d < bd && Math.abs(dx) < TW / 2 && Math.abs(dy) < TH) {
          bd = d;
          best = { q, r };
        }
      }
    return best;
  }

  function reach(u) {
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
        if (unitAt(nq, nr)) return;
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
  function dist(a, b) {
    return Math.abs(a.q - b.q) + Math.abs(a.r - b.r);
  }

  function hitChance(att, def, ignoreCover) {
    let c = att.aim;
    const cover = ignoreCover ? 0 : grid[def.r][def.q].cover || 0;
    c -= cover * 100;
    c += (grid[att.r][att.q].h - grid[def.r][def.q].h) * 10;
    c -= Math.max(0, dist(att, def) - att.rng) * 15;
    if (att.jinx) c -= 15;
    if (att.status && att.status.hex > 0) c -= 15; // hexed: attacker less accurate
    if (def.status && def.status.hunker > 0) c -= 20; // hunkered: harder to hit
    return Math.max(5, Math.min(95, Math.round(c)));
  }
  function rollDmg(att) {
    return (
      Math.floor(Math.random() * (att.wmax - att.wmin + 1)) +
      att.wmin +
      Math.floor(att.str / 3)
    );
  }

  function refreshSel() {
    reachable = sel && sel.alive && sel.side === "p" ? reach(sel) : {};
    const ab = $("babilityBtn");
    if (ab) {
      // 1 AP is enough for Hunker Down; individual options gate by their own cost
      ab.disabled = !(sel && sel.side === "p" && sel.ap >= 1);
      ab.textContent = "Abilities";
    }
    const ib = $("bitemsBtn");
    if (ib) ib.disabled = !(sel && sel.side === "p" && sel.ap >= 1);
    renderParty();
    renderTurnOrder();
  }

  function moveTo(u, q, r, cb) {
    const cost = reach(u)[q + "," + r];
    if (cost === undefined) return;
    busy = true;
    const finalize = () => {
      u.px = u.py = undefined;
      u.q = q;
      u.r = r;
      u.ap -= cost;
      if (u.status && u.status.bleed > 0) {
        statusDamage(u, STATUS_META.bleed.dot, "bleed"); // bleed ticks on move
        u.status.bleed--;
      }
      busy = false;
      refreshSel();
      checkEnd();
      cb && cb();
    };
    // When the tab is hidden, requestAnimationFrame is paused — finalize the move
    // instantly so turn flow (especially the enemy AI) never stalls. The move
    // resolves identically; only the slide animation is skipped.
    if (typeof document !== "undefined" && document.hidden) {
      finalize();
      return;
    }
    const sx = u.q,
      sy = u.r,
      steps = 8;
    let i = 0;
    const tick = () => {
      i++;
      u.px = sx + ((q - sx) * i) / steps;
      u.py = sy + ((r - sy) * i) / steps;
      if (i < steps) {
        requestAnimationFrame(tick);
      } else {
        finalize();
      }
    };
    tick();
  }
  function fire(att, def, opts = {}) {
    busy = true;
    const ch = hitChance(att, def, opts.ignoreCover);
    const hit = Math.random() * 100 < ch;
    const muzzle = iso(att.q, att.r, grid[att.r][att.q].h);
    const tgt = iso(def.q, def.r, grid[def.r][def.q].h);
    for (let k = 0; k < 8; k++)
      particles.push({
        x: muzzle.x,
        y: muzzle.y - 22,
        vx: (tgt.x - muzzle.x) / 14 + (Math.random() - 0.5) * 2,
        vy: (tgt.y - muzzle.y) / 14 + (Math.random() - 0.5) * 2,
        life: 14,
        c: PAL.amber,
      });
    setTimeout(() => {
      if (hit) {
        let dmg = Math.round(rollDmg(att) * (opts.mult || 1));
        if (def.status && def.status.marked > 0) dmg = Math.round(dmg * 1.3); // marked
        if (def.armorDef) dmg = Math.max(1, dmg - def.armorDef); // armor soaks (Pass 6)
        def.hp -= dmg;
        def.flash = 10;
        shake = 8;
        for (let k = 0; k < 12; k++)
          particles.push({
            x: tgt.x,
            y: tgt.y - 22,
            vx: (Math.random() - 0.5) * 5,
            vy: -Math.random() * 4 - 1,
            life: 18,
            c: PAL.blood,
          });
        floaters.push({
          x: tgt.x,
          y: tgt.y - 40,
          t: "-" + dmg,
          life: 42,
          c: PAL.blood,
        });
        log(att.name + " hits " + def.name + " for " + dmg);
        if (opts.status && def.alive)
          applyStatus(def, opts.status, opts.statusN || 2);
        if (att.hexer && def.alive) {
          applyStatus(def, "hex", 2);
          log(def.name + " is hexed — their aim suffers.");
        }
        if (def.hp <= 0) {
          def.alive = false;
          def.downed = 1;
          if (def.side === "e") kills++;
          log(def.name + " falls.");
        } else checkBossPhase(def);
      } else {
        floaters.push({
          x: tgt.x,
          y: tgt.y - 40,
          t: "MISS",
          life: 42,
          c: PAL.parch,
        });
        log(att.name + " misses " + def.name + ".");
      }
      busy = false;
      refreshSel();
      checkEnd();
      opts.cb && opts.cb();
    }, 260);
  }
  function blast(att, def, cb, opts) {
    opts = opts || {}; // {dmgMin, dmgMax, label} — items/divines can hit harder
    busy = true;
    const tgt = iso(def.q, def.r, grid[def.r][def.q].h);
    for (let k = 0; k < 10; k++)
      particles.push({
        x: tgt.x,
        y: tgt.y - 60,
        vx: (Math.random() - 0.5) * 2,
        vy: 2 + Math.random() * 2,
        life: 16,
        c: "#d4763a",
      });
    setTimeout(() => {
      shake = 14;
      for (let k = 0; k < 26; k++)
        particles.push({
          x: tgt.x,
          y: tgt.y - 18,
          vx: (Math.random() - 0.5) * 8,
          vy: -Math.random() * 6,
          life: 22,
          c: k % 2 ? PAL.amber : PAL.blood,
        });
      const caught = all().filter(
        (u) => Math.abs(u.q - def.q) <= 1 && Math.abs(u.r - def.r) <= 1,
      );
      const lo = opts.dmgMin || 4,
        hi = opts.dmgMax || 7;
      caught.forEach((u) => {
        let dmg = Math.floor(Math.random() * (hi - lo + 1)) + lo;
        if (u.armorDef) dmg = Math.max(1, dmg - u.armorDef); // armor soaks (Pass 6)
        u.hp -= dmg;
        u.flash = 10;
        const p = iso(u.q, u.r, grid[u.r][u.q].h);
        floaters.push({
          x: p.x,
          y: p.y - 40,
          t: "-" + dmg,
          life: 42,
          c: PAL.blood,
        });
        if (u.hp <= 0) {
          u.alive = false;
          u.downed = 1;
          if (u.side === "e") kills++;
          log(u.name + " falls.");
        } else checkBossPhase(u);
      });
      log(
        att.name +
          "'s " +
          (opts.label || "dynamite") +
          " catches " +
          caught.length +
          " in the blast!",
      );
      busy = false;
      refreshSel();
      checkEnd();
      cb && cb();
    }, 300);
  }

  // ---- multi-phase boss: at 50% HP the Deacon's god answers ----
  function triggerBossPhase(b) {
    b.enraged = true;
    b.str += 3;
    b.aim += 12;
    b.wmax += 4;
    b.quick += 2;
    b.hp = Math.min(b.maxHp, b.hp + Math.round(b.maxHp * 0.25)); // second wind
    shake = 18;
    const p = iso(b.q, b.r, grid[b.r][b.q].h);
    floaters.push({
      x: p.x,
      y: p.y - 56,
      t: "UNBOUND",
      life: 60,
      c: "#9a6ab8",
    });
    log(b.name + " rises UNBOUND — his god answers. The dead crawl up!");
    // raise up to 2 Risen Dead at free spawns
    const tmpl =
      typeof ENEMY_CATALOG !== "undefined"
        ? ENEMY_CATALOG.find((e) => e.id === "walkin_dead")
        : null;
    if (tmpl) {
      const taken = new Set(all().map((u) => u.q + "," + u.r));
      let added = 0;
      for (const [q, r] of SPAWNS) {
        if (added >= 2) break;
        if (taken.has(q + "," + r)) continue;
        const m = enemyToUnit(tmpl, 90 + added);
        m.name = "Risen Dead";
        m.q = q;
        m.r = r;
        enemies.push(m);
        taken.add(q + "," + r);
        added++;
      }
    }
    refreshSel();
  }
  function checkBossPhase(u) {
    if (u && u.boss && u.alive && !u.enraged && u.hp <= u.maxHp / 2)
      triggerBossPhase(u);
  }

  function enemyTurn() {
    // act fastest-first so `quick` is a real stat (the turn-order bar reflects this)
    const queue = enemies
      .filter((e) => e.alive)
      .sort((a, b) => (b.quick || 0) - (a.quick || 0));
    let idx = 0;
    const step = () => {
      if (!active) return;
      if (idx >= queue.length) {
        endEnemy();
        return;
      }
      const e = queue[idx];
      e.ap = e.maxAp;
      tickStatus(e); // burn/decrements at the start of this enemy's turn
      if (checkEnd()) return;
      const act = () => {
        if (!active) return;
        if (!e.alive) {
          idx++;
          setTimeout(step, 100);
          return;
        }
        const alivePlayers = players.filter((p) => p.alive);
        // Pass 10: zealots berserk once they're bloodied
        if (e.zealot && !e.berserk && e.hp <= e.maxHp / 2) {
          e.berserk = true;
          e.aim += 10;
          e.wmax += 2;
          const zp = iso(e.q, e.r, grid[e.r][e.q].h);
          floaters.push({
            x: zp.x,
            y: zp.y - 52,
            t: "ZEALOTRY",
            life: 48,
            c: "#5B7FAA",
          });
          log(e.name + " burns with zealotry — nothing holds them back!");
        }
        // Pass 10: behavior-driven target selection
        let tgt;
        if (e.flanker) {
          // wolves cut the weakest straggler from the herd
          tgt = alivePlayers.slice().sort((a, b) => a.hp - b.hp)[0];
        } else if (e.swarmer) {
          tgt = alivePlayers.slice().sort((a, b) => dist(e, a) - dist(e, b))[0];
        } else {
          const inRng = alivePlayers.filter((p) => dist(e, p) <= e.rng + 1);
          // focus the weakest target in range; otherwise approach the nearest
          tgt = inRng.length
            ? inRng.slice().sort((a, b) => a.hp - b.hp)[0]
            : alivePlayers.slice().sort((a, b) => dist(e, a) - dist(e, b))[0];
        }
        if (!tgt) {
          idx++;
          setTimeout(step, 150);
          return;
        }
        // Pass 10: sentries are emplacements — they never chase
        if (e.sentry && dist(e, tgt) > e.rng + 1) {
          idx++;
          setTimeout(step, 120);
          return;
        }
        if (dist(e, tgt) <= e.rng + 1 && e.ap >= 2) {
          e.ap -= 2;
          sel = e;
          const cluster = alivePlayers.filter(
            (p) => Math.abs(p.q - tgt.q) <= 1 && Math.abs(p.r - tgt.r) <= 1,
          ).length;
          if (e.bomber || (e.slammer && cluster >= 2)) {
            blast(e, tgt, () => setTimeout(act, 180)); // dynamite / golem slam (AoE)
          } else fire(e, tgt, { cb: () => setTimeout(act, 180) });
          return;
        }
        if (e.blinker && e.ap >= 1 && dist(e, tgt) > e.rng) {
          const spots = [];
          for (let r = 0; r < ROWS; r++)
            for (let q = 0; q < COLS; q++) {
              if (grid[r][q].h >= 2 || unitAt(q, r)) continue;
              const d = Math.abs(q - tgt.q) + Math.abs(r - tgt.r);
              if (d >= 1 && d <= e.rng) spots.push({ q, r, d });
            }
          if (spots.length) {
            const s = spots[Math.floor(Math.random() * spots.length)];
            const from = iso(e.q, e.r, grid[e.r][e.q].h),
              to = iso(s.q, s.r, grid[s.r][s.q].h);
            [from, to].forEach((p) => {
              for (let k = 0; k < 10; k++)
                particles.push({
                  x: p.x,
                  y: p.y - 22,
                  vx: (Math.random() - 0.5) * 3,
                  vy: -Math.random() * 2,
                  life: 16,
                  c: "#5a8a8a",
                });
            });
            e.q = s.q;
            e.r = s.r;
            e.ap -= 1;
            log(e.name + " steps through the dust.");
            setTimeout(act, 200);
            return;
          }
        }
        const rc = reach(e);
        // Pass 10: cover appetite varies by temperament — cover-users prize it,
        // berserk zealots and swarmers charge straight in.
        const coverW = e.coverer ? 2.5 : e.berserk || e.swarmer ? 0 : 1;
        let best = null,
          // closer to the target is better; cover breaks ties (enemies seek cover)
          bestScore = dist(e, tgt) * 2 - coverW * (grid[e.r][e.q].cover || 0);
        Object.keys(rc).forEach((k) => {
          const [q, r] = k.split(",").map(Number);
          const d = Math.abs(q - tgt.q) + Math.abs(r - tgt.r);
          const score = d * 2 - coverW * (grid[r][q].cover || 0);
          if (score < bestScore) {
            bestScore = score;
            best = [q, r];
          }
        });
        if (best && e.ap > 0) {
          moveTo(e, best[0], best[1], () => setTimeout(act, 150));
        } else {
          idx++;
          setTimeout(step, 150);
        }
      };
      setTimeout(act, 200);
    };
    step();
  }
  function endEnemy() {
    turn = "p";
    turnsTaken++;
    players.forEach((p) => {
      if (p.alive) {
        p.ap = p.maxAp;
        tickStatus(p); // burn/decrements at the start of the player's turn
      }
    });
    if (checkEnd()) return;
    sel = players.find((p) => p.alive);
    abilityMode = false;
    log("— Your move —");
    refreshSel();
  }

  let lastResult = null;
  function checkEnd() {
    if (ended) return true;
    if (!players.some((p) => p.alive)) {
      finish(false);
      return true;
    }
    if (!enemies.some((e) => e.alive)) {
      finish(true);
      return true;
    }
    return false;
  }
  function finish(win) {
    ended = true;
    busy = true;
    const survivors = players.filter((p) => p.alive).length;
    const xp = kills * 10 + (win ? 25 : 0);
    // Pass 4 (v1.1): wounds persist — write battle damage back to the roster.
    // The fallen aren't dead-dead; they cling on at 1 HP until a Rest/Doc/heal.
    if (DF.state && DF.state.party && DF.state.party.length) {
      players.forEach((u) => {
        const m = DF.state.party.find((p) => p.uid === u.id);
        if (!m) return;
        m.hpDamage = u.alive
          ? Math.max(0, u.maxHp - u.hp)
          : Math.max(0, u.maxHp - 1);
      });
    }
    // Phase 1b: victory pleases the gods of the party (+1 favor each).
    if (win && DF.state && DF.state.favor) {
      const gods = new Set();
      players.forEach((p) => {
        const g = p.god || (DF.ARCH_GOD && DF.ARCH_GOD[p.archetype]);
        if (g) gods.add(g);
      });
      gods.forEach((g) => {
        DF.state.favor[g] = (DF.state.favor[g] || 0) + 1;
      });
    }
    if (DF.saveGame) DF.saveGame();
    lastResult = { win, kills, turns: turnsTaken, survivors, xp };
    const b = $("bbanner"),
      bt = $("bbannerTitle");
    bt.textContent = win ? "THE DUST SETTLES" : "WIPED OUT";
    bt.style.color = win ? PAL.amber : PAL.blood;
    $("bbannerSub").textContent =
      (win ? "Enemies broken" : "The dust takes you") +
      " · " +
      kills +
      " kills · " +
      turnsTaken +
      " turns · +" +
      xp +
      " XP";
    b.style.display = "flex";
  }

  function onCanvasClick(e) {
    if (busy || turn !== "p" || !active) return;
    const p = fit.toLocal(e.clientX, e.clientY);
    const t = tileUnderMouse(p.x, p.y);
    if (!t) return;
    const occ = unitAt(t.q, t.r);
    if (occ && occ.side === "p" && occ.alive) {
      sel = occ;
      abilityMode = false;
      itemMode = null;
      hideAbilityMenu();
      hideItemMenu();
      refreshSel();
      return;
    }
    if (occ && occ.side === "e" && occ.alive && sel) {
      if (itemMode === "ashfall_charge") {
        itemMode = null;
        if (sel.ap < 1) return;
        sel.ap -= 1;
        consumeItem("ashfall_charge");
        blast(sel, occ, null, {
          dmgMin: 6,
          dmgMax: 10,
          label: "Ashfall charge",
        });
        return;
      }
      if (abilityMode) {
        doAbility(occ);
        return;
      }
      if (dist(sel, occ) <= sel.rng + 1 && sel.ap >= 2) {
        sel.ap -= 2;
        fire(sel, occ, { ignoreCover: sel.wIC }); // Hex Focus pierces cover
      } else log("Out of range or no AP.");
      return;
    }
    if (sel && !abilityMode && reachable[t.q + "," + t.r] !== undefined)
      moveTo(sel, t.q, t.r);
  }
  function endPlayerTurn() {
    if (busy || turn !== "p" || !active) return;
    turn = "e";
    abilityMode = false;
    itemMode = null;
    hideAbilityMenu();
    hideItemMenu();
    players.forEach((p) => (p.jinx = 0));
    log("Enemies stir...");
    enemyTurn();
  }
  function hideAbilityMenu() {
    const menu = $("babilityMenu");
    if (menu) menu.style.display = "none";
  }

  // ---- Pass 7 (v1.1): consumables usable in battle (1 AP each) -------------
  let itemMode = null; // consumable id awaiting a target click (ashfall_charge)
  function invCount(id) {
    return (DF.state && DF.state.inventory && DF.state.inventory[id]) || 0;
  }
  function consumeItem(id) {
    if (!DF.state) return;
    DF.state.inventory = DF.state.inventory || {};
    DF.state.inventory[id] = Math.max(0, (DF.state.inventory[id] || 0) - 1);
    if (DF.saveGame) DF.saveGame();
  }
  function hideItemMenu() {
    const m = $("bitemMenu");
    if (m) m.style.display = "none";
  }
  function openItemMenu() {
    if (busy || turn !== "p" || !(sel && sel.side === "p" && sel.ap >= 1))
      return;
    const m = $("bitemMenu");
    if (!m) return;
    if (m.style.display !== "none") {
      hideItemMenu();
      return;
    }
    hideAbilityMenu();
    while (m.firstChild) m.removeChild(m.firstChild);
    const defs = [
      { id: "bandages", label: "Bandages — heal 8" },
      { id: "ashfall_charge", label: "Ashfall Charge — AoE 6-10" },
      { id: "smelling_salts", label: "Smelling Salts — revive the fallen" },
    ];
    let any = false;
    defs.forEach((d) => {
      const n = invCount(d.id);
      if (!n) return;
      any = true;
      const b = document.createElement("button");
      b.className = "btn abil-opt";
      b.textContent = d.label + " ×" + n + " · 1 AP";
      b.onclick = () => useItem(d.id);
      m.appendChild(b);
    });
    if (!any) {
      const p = document.createElement("div");
      p.className = "hint";
      p.textContent = "Saddlebags empty — stock up at an Outfitter.";
      m.appendChild(p);
    }
    m.style.display = "flex";
  }
  function useItem(id) {
    hideItemMenu();
    if (!sel || sel.ap < 1 || busy) return;
    if (id === "bandages") {
      sel.ap -= 1;
      consumeItem(id);
      const amt = 8;
      sel.hp = Math.min(sel.maxHp, sel.hp + amt);
      const p = iso(sel.q, sel.r, grid[sel.r][sel.q].h);
      floaters.push({
        x: p.x,
        y: p.y - 40,
        t: "+" + amt,
        life: 42,
        c: PAL.teal,
      });
      log(sel.name + " ties off the wound (+" + amt + ").");
      refreshSel();
    } else if (id === "smelling_salts") {
      const fallen = players.find((p) => p.downed && !p.alive);
      if (!fallen) {
        log("No one needs the salts — the crew still stands.");
        return;
      }
      sel.ap -= 1;
      consumeItem(id);
      fallen.alive = true;
      fallen.downed = 0;
      fallen.hp = 5;
      fallen.ap = 0;
      fallen.status = { burn: 0, bleed: 0, hex: 0, marked: 0, hunker: 0 };
      log(sel.name + " brings " + fallen.name + " around with the salts.");
      refreshSel();
    } else if (id === "ashfall_charge") {
      itemMode = id;
      abilityMode = false;
      log("Ashfall Charge: pick a target");
    }
  }
  function openAbilityMenu() {
    if (!(sel && sel.side === "p" && sel.ap >= 1)) return;
    const menu = $("babilityMenu");
    if (!menu) return;
    if (menu.style.display !== "none" && menu.dataset.for === sel.id) {
      hideAbilityMenu();
      return;
    }
    while (menu.firstChild) menu.removeChild(menu.firstChild);
    const opts = (sel.abilities || [sel.ability]).slice();
    if (sel.divine && !sel.divineUsed) opts.push(sel.divine);
    opts.push("Hunker Down"); // universal defensive action (1 AP)
    const god = sel.god || (DF.ARCH_GOD && DF.ARCH_GOD[sel.archetype]);
    const favor =
      DF.state && DF.state.favor && god ? DF.state.favor[god] || 0 : 0;
    opts.forEach((name) => {
      const b = document.createElement("button");
      const isDiv = name === sel.divine;
      b.className = "btn abil-opt" + (isDiv ? " divine" : "");
      if (isDiv) {
        b.textContent =
          "✦ " + name + " (favor " + favor + (favor >= 3 ? "★" : "") + ")";
        // needs favor AND enough AP (divine consumes the whole turn)
        if (favor < 1 || sel.ap < 2) b.disabled = true;
      } else {
        b.textContent = name + " · " + abilCost(name) + " AP";
        if (sel.ap < abilCost(name)) b.disabled = true; // can't afford it
      }
      b.onclick = () => chooseAbility(name);
      menu.appendChild(b);
    });
    menu.dataset.for = sel.id;
    menu.style.display = "flex";
  }
  function chooseAbility(name) {
    if (!sel) return;
    hideAbilityMenu();
    if (name === "Hunker Down") {
      if (sel.ap < 1) return;
      sel.ap -= 1;
      applyStatus(sel, "hunker", 2);
      log(sel.name + " hunkers down — harder to hit.");
      refreshSel();
      return;
    }
    if (name !== sel.divine && sel.ap < abilCost(name)) {
      log("Not enough AP for " + name + ".");
      return;
    }
    sel.ability = name;
    if (isHeal(name)) {
      // Lay on Hands prefers a fallen ally (revive) over a hurt one
      const fallen =
        name === "Lay on Hands"
          ? players.find((p) => p.downed && !p.alive)
          : null;
      const allies = players.filter((p) => p.alive);
      const who =
        fallen ||
        allies.slice().sort((a, b) => a.hp / a.maxHp - b.hp / b.maxHp)[0] ||
        sel;
      doAbility(who);
      return;
    }
    abilityMode = true;
    log(name + ": pick a target");
  }
  function isHeal(a) {
    return a === "Lay on Hands" || a === "Soul Drain";
  }
  function doAbility(tgt) {
    abilityMode = false;
    const a = sel.ability;
    // safety net: never let a non-divine ability drive AP negative
    if (a && a !== sel.divine && sel.ap < abilCost(a)) {
      log("Not enough AP for " + a + ".");
      refreshSel();
      return;
    }
    if (a && a === sel.divine) {
      if (sel.divineUsed) {
        log("The god has already answered this fight.");
        return;
      }
      // Phase 1b: divines require favor. Read the persistent pool (live) or the
      // unit snapshot (harness). 1 favor is spent; 3+ favor empowers the strike.
      const god =
        sel.god || (DF.ARCH_GOD && DF.ARCH_GOD[sel.archetype]) || null;
      const pool =
        DF.state && DF.state.favor && god
          ? DF.state.favor[god] || 0
          : sel.favor || 0;
      if (pool < 1) {
        log(sel.name + "'s god is silent — earn favor at a shrine first.");
        return;
      }
      const empowered = pool >= 3;
      if (DF.state && DF.state.favor && god)
        DF.state.favor[god] = Math.max(0, (DF.state.favor[god] || 0) - 1);
      sel.favor = Math.max(0, (sel.favor || pool) - 1);
      sel.divineUsed = true;
      sel.ap = 0;
      shake = 16;
      log(sel.name + " channels " + a + (empowered ? " — EMPOWERED!" : "!"));
      if (a === "Vulcan's Forgefire" || a === "Perun's Thunder") {
        blast(sel, tgt);
        setTimeout(() => {
          if (tgt) blast(sel, tgt);
        }, 220);
        if (empowered)
          setTimeout(() => {
            if (tgt) blast(sel, tgt);
          }, 440);
      } else {
        const sv = sel.aim;
        sel.aim = 999;
        fire(sel, tgt, {
          ignoreCover: true,
          mult: empowered ? 3.5 : 2.5,
          status: empowered ? "marked" : null,
          statusN: 2,
          cb: () => {
            sel.aim = sv;
          },
        });
      }
      refreshSel();
      return;
    }
    if (a === "Fan the Hammer") {
      sel.ap -= abilCost(a);
      log("Fan the Hammer — three shots!");
      let n = 0;
      const s = () => {
        if (n++ < 3 && tgt.alive) {
          const sv = sel.aim;
          sel.aim -= 10;
          fire(sel, tgt, {
            cb: () => {
              sel.aim = sv;
              setTimeout(s, 160);
            },
          });
        }
      };
      s();
    } else if (a === "Hex Bolt") {
      sel.ap -= 2;
      log("Hex Bolt ignores cover — and hexes!");
      fire(sel, tgt, { ignoreCover: true, status: "hex", statusN: 2 });
    } else if (a === "Ashfall Grenade") {
      sel.ap -= 2;
      log(sel.name + " lobs an Ashfall grenade!");
      blast(sel, tgt);
    } else if (a === "Called Shot") {
      sel.ap -= abilCost(a);
      log("Called Shot — dead to rights, and marked.");
      const sv = sel.aim;
      sel.aim = 999;
      fire(sel, tgt, {
        status: "marked",
        statusN: 2,
        cb: () => {
          sel.aim = sv;
        },
      });
    } else if (a === "Lay on Hands" || a === "Soul Drain") {
      sel.ap -= abilCost(a);
      const amt = 6 + Math.floor(Math.random() * 5);
      const who = a === "Soul Drain" ? sel : tgt;
      if (who.downed) {
        who.alive = true;
        who.downed = 0;
        who.status = { burn: 0, bleed: 0, hex: 0, marked: 0, hunker: 0 };
        who.hp = amt;
        who.ap = 0; // revived — back on their feet next turn
        log(sel.name + " pulls " + who.name + " back from the brink.");
      } else {
        who.hp = Math.min(who.maxHp, who.hp + amt);
        log(
          sel.name +
            (a === "Soul Drain"
              ? " drains the void (+"
              : " lays hands on " + who.name + " (+") +
            amt +
            ").",
        );
      }
      const p = iso(who.q, who.r, grid[who.r][who.q].h);
      floaters.push({
        x: p.x,
        y: p.y - 40,
        t: "+" + amt,
        life: 42,
        c: PAL.teal,
      });
      refreshSel();
    } else if (a === "Gut Shot" || a === "Both Barrels") {
      sel.ap -= 2;
      log(sel.name + " — " + a + "! (bleeding wound)");
      fire(sel, tgt, { mult: 1.8, status: "bleed", statusN: 3 });
    } else if (a === "Arc Shock") {
      sel.ap -= 2;
      log("Arc Shock crackles through the cover!");
      fire(sel, tgt, { ignoreCover: true, mult: 1.4 });
    } else if (a === "Holy Smite") {
      sel.ap -= 2;
      log(sel.name + " calls down Holy Smite!");
      fire(sel, tgt, { mult: 1.6 });
    } else if (a === "Pistol Whip") {
      sel.ap -= 2;
      log(sel.name + " pistol-whips " + tgt.name + "!");
      fire(sel, tgt, { mult: 1.8 });
    } else {
      sel.ap -= 2;
      fire(sel, tgt, { mult: 1.5 });
    }
  }

  function tileColor(cell) {
    return biome.floors[Math.min(2, cell.h)];
  }
  function drawTile(q, r) {
    const cell = grid[r][q];
    const p = iso(q, r, cell.h);
    const top = [
      [p.x, p.y],
      [p.x + TW / 2, p.y + TH / 2],
      [p.x, p.y + TH],
      [p.x - TW / 2, p.y + TH / 2],
    ];
    if (cell.h > 0) {
      X.fillStyle = "#241a0e";
      X.beginPath();
      X.moveTo(p.x - TW / 2, p.y + TH / 2);
      X.lineTo(p.x, p.y + TH);
      X.lineTo(p.x, p.y + TH + cell.h * 18);
      X.lineTo(p.x - TW / 2, p.y + TH / 2 + cell.h * 18);
      X.closePath();
      X.fill();
      X.fillStyle = "#1a120a";
      X.beginPath();
      X.moveTo(p.x + TW / 2, p.y + TH / 2);
      X.lineTo(p.x, p.y + TH);
      X.lineTo(p.x, p.y + TH + cell.h * 18);
      X.lineTo(p.x + TW / 2, p.y + TH / 2 + cell.h * 18);
      X.closePath();
      X.fill();
    }
    X.fillStyle = tileColor(cell);
    X.beginPath();
    X.moveTo(top[0][0], top[0][1]);
    top.slice(1).forEach((t) => X.lineTo(t[0], t[1]));
    X.closePath();
    X.fill();
    X.strokeStyle = "rgba(0,0,0,.35)";
    X.lineWidth = 1;
    X.stroke();
    const k = q + "," + r;
    if (turn === "p" && sel && !abilityMode && reachable[k] !== undefined) {
      X.fillStyle = "rgba(78,205,196,.18)";
      X.fill();
      X.strokeStyle = "rgba(78,205,196,.5)";
      X.stroke();
    }
    if (C.hoverTile && C.hoverTile.q === q && C.hoverTile.r === r) {
      X.fillStyle = "rgba(212,168,67,.16)";
      X.fill();
      // Pass 8: show the AP cost of moving to the hovered reachable tile
      if (turn === "p" && sel && !abilityMode && reachable[k] !== undefined) {
        X.fillStyle = "rgba(212,197,169,.95)";
        X.font = "10px 'Special Elite'";
        X.textAlign = "center";
        X.fillText(reachable[k] + " AP", p.x, p.y + TH / 2 + 4);
      }
    }
    if (cell.deco === "crate") {
      X.fillStyle = "#6b4a26";
      X.fillRect(p.x - 11, p.y + TH / 2 - 20, 22, 22);
      X.strokeStyle = "#3a2814";
      X.strokeRect(p.x - 11, p.y + TH / 2 - 20, 22, 22);
    }
    if (cell.deco === "cactus") {
      X.strokeStyle = "#5a7a4a";
      X.lineWidth = 5;
      X.beginPath();
      X.moveTo(p.x, p.y + TH / 2);
      X.lineTo(p.x, p.y + TH / 2 - 22);
      X.moveTo(p.x, p.y + TH / 2 - 12);
      X.lineTo(p.x - 8, p.y + TH / 2 - 18);
      X.moveTo(p.x, p.y + TH / 2 - 15);
      X.lineTo(p.x + 8, p.y + TH / 2 - 20);
      X.stroke();
      X.lineWidth = 1;
    }
    // ---- Pass 9 biome decos (cheap canvas prims, same silhouette budget) ----
    const fy = p.y + TH / 2; // feet line of the tile
    if (cell.deco === "rock") {
      X.fillStyle = "#6e523a";
      X.beginPath();
      X.ellipse(p.x, fy - 8, 12, 9, 0, 0, 7);
      X.fill();
      X.fillStyle = "#54402c";
      X.beginPath();
      X.ellipse(p.x + 5, fy - 5, 7, 5, 0, 0, 7);
      X.fill();
    }
    if (cell.deco === "barrel") {
      X.fillStyle = "#7a5a30";
      X.fillRect(p.x - 8, fy - 18, 16, 18);
      X.strokeStyle = "#3a2814";
      X.strokeRect(p.x - 8, fy - 18, 16, 18);
      X.beginPath();
      X.moveTo(p.x - 8, fy - 9);
      X.lineTo(p.x + 8, fy - 9);
      X.stroke();
    }
    if (cell.deco === "grave") {
      X.fillStyle = "#8a857a";
      X.fillRect(p.x - 7, fy - 18, 14, 18);
      X.beginPath();
      X.arc(p.x, fy - 18, 7, Math.PI, 0);
      X.fill();
      X.strokeStyle = "#4f4a40";
      X.strokeRect(p.x - 7, fy - 14, 14, 2);
    }
    if (cell.deco === "bone") {
      X.strokeStyle = "#d8d2c0";
      X.lineWidth = 3;
      X.beginPath();
      X.moveTo(p.x - 8, fy - 4);
      X.quadraticCurveTo(p.x, fy - 20, p.x + 8, fy - 4);
      X.stroke();
      X.lineWidth = 1;
    }
    if (cell.deco === "pipe") {
      X.fillStyle = "#8899aa";
      X.fillRect(p.x - 4, fy - 26, 8, 26);
      X.fillStyle = "#b08830";
      X.fillRect(p.x - 6, fy - 26, 12, 4);
    }
    if (cell.deco === "ember") {
      const g2 = Math.sin(Date.now() / 260 + q * 3 + r) * 0.5 + 0.5;
      X.fillStyle = "rgba(232,112,79," + (0.35 + 0.4 * g2) + ")";
      X.beginPath();
      X.arc(p.x, fy - 6, 6, 0, 7);
      X.fill();
      X.fillStyle = "#d4763a";
      X.beginPath();
      X.arc(p.x, fy - 6, 2.5, 0, 7);
      X.fill();
    }
    if (cell.deco === "spire") {
      X.fillStyle = "#3d4a50";
      X.beginPath();
      X.moveTo(p.x - 7, fy);
      X.lineTo(p.x, fy - 28);
      X.lineTo(p.x + 7, fy);
      X.closePath();
      X.fill();
    }
    if (cell.deco === "wisp") {
      const g3 = Math.sin(Date.now() / 340 + q + r * 2) * 0.5 + 0.5;
      X.fillStyle = "rgba(42,250,199," + (0.2 + 0.35 * g3) + ")";
      X.beginPath();
      X.arc(p.x, fy - 12 - g3 * 4, 4, 0, 7);
      X.fill();
    }
  }
  function drawUnit(u) {
    const q = u.px !== undefined ? u.px : u.q,
      r = u.py !== undefined ? u.py : u.r;
    const cell =
      grid[Math.round(u.r)] && grid[Math.round(u.r)][Math.round(u.q)];
    const p = iso(q, r, cell ? cell.h : 0);
    const bob = Math.sin(Date.now() / 400 + u.q) * 1.5;
    X.fillStyle = "rgba(0,0,0,.4)";
    X.beginPath();
    X.ellipse(p.x, p.y + TH / 2 + 2, 14, 6, 0, 0, 7);
    X.fill();
    const flash = u.flash > 0;
    const by = p.y + TH / 2 + bob; // feet line
    // REAL pixel sprite (src/sprites.js) — replaces the old canvas-block figure
    if (typeof drawSprite === "function" && typeof spriteFor === "function") {
      const sc = 3; // 16x20 sprite -> 48x60 px (readable at iso zoom)
      drawSprite(
        X,
        spriteFor(u),
        Math.round(p.x - 8 * sc),
        Math.round(by - 19 * sc),
        sc,
        { flash },
      );
    } else {
      const skin = "#e8c8a0",
        dark = "#2a1d0f";
      X.fillStyle = flash ? "#fff" : dark;
      X.fillRect(p.x - 5, by - 8, 3, 8);
      X.fillRect(p.x + 2, by - 8, 3, 8);
      X.fillRect(p.x - 8, by - 18, 2, 9);
      X.fillRect(p.x + 6, by - 18, 2, 9);
      X.fillStyle = flash ? "#fff" : u.color;
      X.fillRect(p.x - 6, by - 20, 12, 13);
      X.fillStyle = flash ? "#fff" : skin;
      X.fillRect(p.x - 4, by - 27, 8, 7);
      X.fillStyle = flash ? "#fff" : dark;
      X.fillRect(p.x - 8, by - 28, 16, 2);
      X.fillRect(p.x - 4, by - 33, 8, 5);
    }
    if (u === sel && u.alive) {
      X.strokeStyle = PAL.amber;
      X.lineWidth = 2;
      X.beginPath();
      X.ellipse(p.x, p.y + TH / 2 + 2, 17, 8, 0, 0, 7);
      X.stroke();
      X.lineWidth = 1;
    }
    if (u.jinx) {
      X.strokeStyle = "#9a6ab8";
      X.lineWidth = 2;
      X.beginPath();
      X.ellipse(p.x, p.y + TH / 2 - 38 + bob, 9, 9, 0, 0, 7);
      X.stroke();
      X.lineWidth = 1;
    }
    const bw = 26;
    X.fillStyle = "#2a1d0f";
    X.fillRect(p.x - bw / 2, p.y + TH / 2 - 54 + bob, bw, 4);
    X.fillStyle = u.side === "p" ? PAL.teal : PAL.blood;
    X.fillRect(
      p.x - bw / 2,
      p.y + TH / 2 - 54 + bob,
      bw * Math.max(0, u.hp / u.maxHp),
      4,
    );
    if (u.flash > 0) u.flash--;
  }
  function frame() {
    if (!active) return;
    X.clearRect(0, 0, C.width, C.height);
    X.save();
    if (shake > 0) {
      X.translate((Math.random() - 0.5) * shake, (Math.random() - 0.5) * shake);
      shake *= 0.85;
      if (shake < 0.5) shake = 0;
    }
    const g = X.createRadialGradient(450, 300, 40, 450, 300, 460);
    g.addColorStop(0, "rgba(212,168,67,.06)");
    g.addColorStop(1, "rgba(0,0,0,0)");
    X.fillStyle = g;
    X.fillRect(0, 0, 900, 620);
    for (let s = 0; s < COLS + ROWS; s++)
      for (let r = 0; r < ROWS; r++) {
        const q = s - r;
        if (q >= 0 && q < COLS) drawTile(q, r);
      }
    all()
      .sort((a, b) => a.q + a.r - (b.q + b.r))
      .forEach(drawUnit);
    particles = particles.filter((pt) => pt.life > 0);
    particles.forEach((pt) => {
      pt.x += pt.vx;
      pt.y += pt.vy;
      pt.vy += 0.15;
      pt.life--;
      X.globalAlpha = pt.life / 18;
      X.fillStyle = pt.c;
      X.fillRect(pt.x, pt.y, 3, 3);
      X.globalAlpha = 1;
    });
    floaters = floaters.filter((f) => f.life > 0);
    floaters.forEach((f) => {
      f.y -= 0.7;
      f.life--;
      X.globalAlpha = Math.min(1, f.life / 20);
      X.fillStyle = f.c;
      X.font = "bold 16px 'Special Elite'";
      X.textAlign = "center";
      X.fillText(f.t, f.x, f.y);
      X.globalAlpha = 1;
    });
    drawPreview();
    X.restore();
    requestAnimationFrame(frame);
  }

  // ---- Pass 8 (v1.1): combat preview — hover an enemy to see the odds ------
  // Mirrors doAbility's numbers; divines assume the unempowered strike.
  const PREVIEW_FX = {
    "Fan the Hammer": { shots: 3, aimMod: -10 },
    "Hex Bolt": { ic: true },
    "Ashfall Grenade": { blast: [4, 7] },
    "Called Shot": { guaranteed: true },
    "Gut Shot": { mult: 1.8 },
    "Both Barrels": { mult: 1.8 },
    "Arc Shock": { mult: 1.4, ic: true },
    "Holy Smite": { mult: 1.6 },
    "Pistol Whip": { mult: 1.8 },
    "Aimed Shot": { mult: 1.5 },
    "Coyote's Gambit": { guaranteed: true, ic: true, mult: 2.5 },
    "Samedi's Embrace": { guaranteed: true, ic: true, mult: 2.5 },
    "Iron Verdict": { guaranteed: true, ic: true, mult: 2.5 },
    "Anansi's Trick": { guaranteed: true, ic: true, mult: 2.5 },
    "Vulcan's Forgefire": { blast: [8, 14] },
    "Perun's Thunder": { blast: [8, 14] },
  };
  function drawPreview() {
    if (turn !== "p" || busy || !sel || !sel.alive || sel.side !== "p") return;
    const t = C.hoverTile;
    if (!t) return;
    const occ = unitAt(t.q, t.r);
    if (!occ || occ.side !== "e" || !occ.alive) return;
    const fx = abilityMode ? PREVIEW_FX[sel.ability] || {} : { ic: sel.wIC };
    const inRange = dist(sel, occ) <= sel.rng + 1;
    let lines;
    if (fx.blast) {
      lines = [sel.ability, "AoE " + fx.blast[0] + "-" + fx.blast[1] + " dmg"];
    } else {
      const sv = sel.aim;
      if (fx.aimMod) sel.aim += fx.aimMod;
      const ch = fx.guaranteed ? 95 : hitChance(sel, occ, fx.ic);
      sel.aim = sv;
      const mult = fx.mult || 1;
      const markedF = occ.status && occ.status.marked > 0 ? 1.3 : 1;
      let lo = Math.round(
        (sel.wmin + Math.floor(sel.str / 3)) * mult * markedF,
      );
      let hi = Math.round(
        (sel.wmax + Math.floor(sel.str / 3)) * mult * markedF,
      );
      if (occ.armorDef) {
        lo = Math.max(1, lo - occ.armorDef);
        hi = Math.max(1, hi - occ.armorDef);
      }
      lines = [
        ch + "% to hit" + (fx.shots ? " ×" + fx.shots : ""),
        lo + "-" + hi + " dmg",
      ];
    }
    if (!inRange && !abilityMode) lines.push("OUT OF RANGE");
    const p = iso(occ.q, occ.r, grid[occ.r][occ.q].h);
    const w = 112,
      h = 15 * lines.length + 12;
    let px = p.x - w / 2,
      py = p.y - 84 - (lines.length - 2) * 8;
    px = Math.max(4, Math.min(C.width - w - 4, px));
    py = Math.max(4, py);
    X.fillStyle = "rgba(20,12,5,.88)";
    X.strokeStyle = "#a0522d";
    X.lineWidth = 1;
    X.beginPath();
    X.rect(px, py, w, h);
    X.fill();
    X.stroke();
    X.font = "11px 'Special Elite'";
    X.textAlign = "center";
    lines.forEach((ln, i) => {
      X.fillStyle =
        ln === "OUT OF RANGE" ? "#c0392b" : i === 0 ? "#d4a843" : "#d4c5a9";
      X.fillText(ln, px + w / 2, py + 15 + i * 15);
    });
  }
  function renderParty() {
    const el = $("bparty");
    if (!el) return;
    while (el.firstChild) el.removeChild(el.firstChild);
    players.forEach((u) => {
      const card = document.createElement("div");
      card.className =
        "unit-card" +
        (u === sel ? " active" : "") +
        (!u.alive ? " downed" : "");
      const n = document.createElement("div");
      n.className = "n";
      n.textContent = u.name;
      card.appendChild(n);
      const role = document.createElement("div");
      role.className = "role";
      role.textContent = u.role;
      card.appendChild(role);
      const bar = document.createElement("div");
      bar.className = "bar";
      const fill = document.createElement("i");
      fill.style.width = Math.max(0, (u.hp / u.maxHp) * 100) + "%";
      bar.appendChild(fill);
      card.appendChild(bar);
      const pips = document.createElement("div");
      pips.className = "pips";
      for (let i = 0; i < u.maxAp; i++) {
        const pip = document.createElement("span");
        pip.className = "pip" + (i < u.ap ? " on" : "");
        pips.appendChild(pip);
      }
      card.appendChild(pips);
      // active status effects (Phase 1a)
      const st = document.createElement("div");
      st.className = "statuses";
      if (u.status) {
        Object.keys(STATUS_META).forEach((k) => {
          if (u.status[k] > 0) {
            const s = document.createElement("span");
            s.className = "stag";
            s.textContent = STATUS_META[k].tag;
            s.style.color = STATUS_META[k].col;
            s.style.borderColor = STATUS_META[k].col;
            s.title = k + " · " + u.status[k] + " turn(s)";
            st.appendChild(s);
          }
        });
      }
      card.appendChild(st);
      el.appendChild(card);
    });
  }

  // ---- turn-order / initiative bar (DOM overlay, fastest-first) ----
  function renderTurnOrder() {
    const host = document.querySelector('[data-scene="battle"]');
    const row = host && host.querySelector("#bturn .trow");
    if (!row) return;
    const order = all()
      .slice()
      .sort(
        (a, b) => (b.quick || 0) - (a.quick || 0) || (a.side === "p" ? -1 : 1),
      );
    while (row.firstChild) row.removeChild(row.firstChild);
    order.slice(0, 9).forEach((u) => {
      const chip = document.createElement("div");
      chip.className = "tchip " + u.side + (u === sel && u.alive ? " act" : "");
      const n = document.createElement("div");
      n.className = "tn";
      n.textContent = (u.name || u.role || "?").split(" ")[0];
      chip.appendChild(n);
      const q = document.createElement("div");
      q.className = "tq";
      q.textContent = u.boss ? "★" + (u.quick || 0) : "⚡" + (u.quick || 0);
      chip.appendChild(q);
      const hp = document.createElement("div");
      hp.className = "thp";
      const fill = document.createElement("i");
      fill.style.width = Math.max(0, (u.hp / u.maxHp) * 100) + "%";
      hp.appendChild(fill);
      chip.appendChild(hp);
      row.appendChild(chip);
    });
  }

  // ---- scene lifecycle ----
  DF.register("battle", {
    enter(params) {
      if (!built) build();
      const roster =
        params.party && params.party.length
          ? params.party
          : DF.state && DF.state.party && DF.state.party.length
            ? DF.state.party
            : DF.makeStarterParty();
      players = roster.slice(0, 4).map(partyToUnit);
      // Phase 1b: snapshot each unit's divine favor from the persistent pool
      players.forEach((u) => {
        const g = u.god || (DF.ARCH_GOD && DF.ARCH_GOD[u.archetype]);
        u.favor = g && DF.state && DF.state.favor ? DF.state.favor[g] || 0 : 0;
      });
      const specs =
        params.enemies && params.enemies.length
          ? params.enemies
          : typeof ENEMY_CATALOG !== "undefined"
            ? [
                ENEMY_CATALOG[0],
                ENEMY_CATALOG[2],
                ENEMY_CATALOG[3],
                ENEMY_CATALOG[4],
              ]
            : [];
      // Phase 1d: scale the encounter to the current party size (no brick walls)
      const scaled = DF.scaleEncounter
        ? DF.scaleEncounter(specs, players.length)
        : specs;
      buildGrid(params.biome); // Pass 9: biome map (defaults to mesa)
      const free = SPAWNS.slice();
      enemies = scaled.map((spec, i) => {
        const u = enemyToUnit(spec, i);
        const [q, r] = free[i] || SPAWNS[i % SPAWNS.length];
        u.q = q;
        u.r = r;
        return u;
      });
      sel = players[0];
      turn = "p";
      reachable = {};
      shake = 0;
      particles = [];
      floaters = [];
      abilityMode = false;
      itemMode = null;
      busy = false;
      kills = 0;
      turnsTaken = 0;
      ended = false;
      logs.length = 0;
      onComplete = params.onComplete || (() => DF.go("results", lastResult));
      $("bwaveLabel").textContent = params.title || "Skirmish at the Crossing";
      $("bbanner").style.display = "none";
      active = true;
      refreshSel();
      requestAnimationFrame(frame);
      log("— Your move —");
    },
    exit() {
      active = false;
    },
    onKey(k) {
      if (k === "Enter" || k === " ") endPlayerTurn();
    },
  });

  // ---- test hook for scripted browser verification ----
  DF.battle = {
    get players() {
      return players;
    },
    get enemies() {
      return enemies;
    },
    get grid() {
      return grid;
    },
    get turn() {
      return turn;
    },
    get busy() {
      return busy;
    },
    get kills() {
      return kills;
    },
    get ended() {
      return ended;
    },
    get result() {
      return lastResult;
    },
    hitChance,
    rollDmg,
    fire,
    reach,
    unitAt,
    dist,
    endPlayerTurn,
    doAbility,
    chooseAbility,
    applyStatus,
    tickStatus,
    STATUS_META,
    forceWin() {
      // dev/test hook: instantly resolve the battle as a win (used to verify the
      // campaign flow end-to-end without auto-playing every turn).
      enemies.forEach((e) => {
        e.alive = false;
        e.hp = 0;
      });
      checkEnd();
    },
    get sel() {
      return sel;
    },
    set sel(u) {
      sel = u;
    },
  };
})();
