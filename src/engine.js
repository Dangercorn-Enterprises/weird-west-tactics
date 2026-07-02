// =============================================
// DUSTFALL ENGINE — scene manager, state, storage, scaling, input
// Classic script (no ES modules) so it runs from file://, a dev server, AND Electron.
// =============================================
(function () {
  "use strict";
  const DF = (window.DF = window.DF || {});

  // Each archetype is devoted to a god; their divine ultimate draws on that
  // god's favor (Phase 1b). Favor is earned at shrines and by winning battles.
  DF.ARCH_GOD = {
    gunslinger: "coyote",
    hexslinger: "samedi",
    tinkerer: "vulcan",
    preacher: "perun",
    lawdog: "perun",
    drifter: "anansi",
  };

  // Pass 9 (v1.1): which battle-map biome each god's turf uses
  DF.GOD_BIOME = {
    coyote: "mesa",
    vulcan: "foundry",
    samedi: "boneyard",
    anansi: "canyon",
    perun: "town",
    sleeper: "hollow",
  };
  DF.biomeFor = function (god) {
    return (god && DF.GOD_BIOME[god]) || "mesa";
  };

  // ---- Storage interface: localStorage (browser) <-> native fs (desktop/Electron) ----
  DF.storage = {
    get native() {
      return window.dfNative && typeof window.dfNative.save === "function"
        ? window.dfNative
        : null;
    },
    save(key, obj) {
      const json = JSON.stringify(obj);
      if (this.native) {
        try {
          this.native.save(key, json);
          return;
        } catch (e) {}
      }
      try {
        localStorage.setItem("dustfall:" + key, json);
      } catch (e) {}
    },
    load(key) {
      if (this.native) {
        try {
          const s = this.native.load(key);
          return s ? JSON.parse(s) : null;
        } catch (e) {
          return null;
        }
      }
      try {
        const s = localStorage.getItem("dustfall:" + key);
        return s ? JSON.parse(s) : null;
      } catch (e) {
        return null;
      }
    },
    wipe(key) {
      if (this.native && this.native.wipe) {
        try {
          this.native.wipe(key);
        } catch (e) {}
      }
      try {
        localStorage.removeItem("dustfall:" + key);
      } catch (e) {}
    },
  };

  // ---- Game state ----
  DF.newGame = function () {
    DF.state = {
      party: [], // player roster (units)
      gold: 300,
      day: 1,
      location: "rustwater", // overworld node id (Phase 2 maps to a real Southwest city)
      visited: {},
      // god id -> favor. Seeded so each divine has one early use; replenished at
      // shrines (+1 / 50g) and by winning battles. Divines consume 1, empower at 3+.
      favor: {
        coyote: 1,
        samedi: 1,
        vulcan: 1,
        perun: 1,
        anansi: 1,
        sleeper: 0,
      },
      corruption: {}, // unit id -> corruption level
      flags: {},
      version: 1,
    };
    return DF.state;
  };
  DF.saveGame = function () {
    DF.storage.save("save", DF.state);
  };
  DF.loadGame = function () {
    const s = DF.storage.load("save");
    if (s && s.version) {
      DF.state = s;
      return true;
    }
    return false;
  };
  DF.hasSave = function () {
    const s = DF.storage.load("save");
    return !!(s && s.version);
  };

  // ---- Scene manager: DOM sections, one visible at a time, shared DF.state ----
  // A scene = { enter(params), exit(), onKey(key,ev) }  — it owns the DOM inside its [data-scene] section.
  DF.scenes = {};
  DF.current = null;
  DF.currentName = null;
  DF.register = function (name, scene) {
    DF.scenes[name] = scene;
  };
  DF.go = function (name, params) {
    const next = DF.scenes[name];
    if (!next) {
      console.warn('DF: no scene "' + name + '"');
      return;
    }
    if (DF.current && DF.current.exit) {
      try {
        DF.current.exit();
      } catch (e) {
        console.error(e);
      }
    }
    document.querySelectorAll("[data-scene]").forEach((el) => {
      el.style.display = el.getAttribute("data-scene") === name ? "" : "none";
    });
    DF.current = next;
    DF.currentName = name;
    if (next.enter) {
      try {
        next.enter(params || {});
      } catch (e) {
        console.error(e);
      }
    }
  };

  // ---- Fixed internal resolution, letterboxed to the window (fullscreen-friendly) ----
  DF.fitCanvas = function (canvas, baseW, baseH) {
    canvas.width = baseW;
    canvas.height = baseH;
    const resize = () => {
      // guard against bogus/headless viewports reporting ~0 width
      const vw = window.innerWidth > 50 ? window.innerWidth : baseW;
      const vh = window.innerHeight > 50 ? window.innerHeight - 8 : baseH;
      const scale = Math.min(vw / baseW, vh / baseH);
      canvas.style.width = Math.max(1, Math.floor(baseW * scale)) + "px";
      canvas.style.height = Math.max(1, Math.floor(baseH * scale)) + "px";
    };
    resize();
    window.addEventListener("resize", resize);
    return {
      resize,
      toLocal(clientX, clientY) {
        const r = canvas.getBoundingClientRect();
        return {
          x: ((clientX - r.left) * baseW) / r.width,
          y: ((clientY - r.top) * baseH) / r.height,
        };
      },
    };
  };

  // ---- Input abstraction (keyboard now; gamepad can register here later) ----
  DF.input = {
    bind() {
      window.addEventListener("keydown", (e) => {
        if (DF.current && DF.current.onKey) DF.current.onKey(e.key, e);
      });
    },
  };

  // ---- party helpers ----
  DF.makeStarterParty = function () {
    // Two pregens to start (matches the v0.3 arena posse); recruit more in towns.
    const picks = ["gunslinger", "hexslinger"];
    return picks.map((aid, i) => {
      const pg = typeof PREGEN !== "undefined" ? PREGEN[aid] : null;
      const arch =
        typeof ARCHETYPES !== "undefined"
          ? ARCHETYPES.find((a) => a.id === aid)
          : null;
      return {
        uid: "p" + i,
        archetype: aid,
        name: pg ? pg.name : arch ? arch.name : "Rider",
        stats: pg ? Object.assign({}, pg.stats) : {},
        level: 1,
        xp: 0,
        god: null,
        gear: { weapon: null, armor: null },
        hpDamage: 0,
        alive: true,
      };
    });
  };

  // ---- progression / leveling (Phase 5) ----
  DF.xpForLevel = function (lvl) {
    return (lvl || 1) * 100;
  }; // XP to reach the next level
  DF.gainXP = function (unit, amount) {
    unit.xp = (unit.xp || 0) + (amount || 0);
    unit.level = unit.level || 1;
    unit.stats = unit.stats || {};
    const reached = [];
    const favored = {
      gunslinger: ["deftness", "quickness"],
      hexslinger: ["cognition", "spirit"],
      tinkerer: ["knowledge", "cognition"],
      preacher: ["spirit", "vigor"],
      lawdog: ["vigor", "mien"],
      drifter: ["nimbleness", "quickness"],
    };
    while (unit.xp >= DF.xpForLevel(unit.level)) {
      unit.xp -= DF.xpForLevel(unit.level);
      unit.level += 1;
      // bible: +2 stats per level. Bump one favored stat + vigor (HP growth).
      const fav = favored[unit.archetype] || ["vigor", "quickness"];
      const s1 = fav[Math.floor(Math.random() * fav.length)];
      unit.stats[s1] = (unit.stats[s1] || 3) + 1;
      unit.stats.vigor = (unit.stats.vigor || 3) + 1;
      reached.push(unit.level);
    }
    return reached; // [] or list of new levels
  };

  // ---- encounter scaling (Phase 1d) ----
  // Normalize enemy difficulty to the current party size so there are no brick
  // walls: a lone pair faces weaker foes, a full posse faces tougher ones.
  // Designed around a 3-strong party. Mirrored exactly in tools/balance_harness.js.
  DF.scaleEncounter = function (specs, partySize) {
    // balance 2026-07-01: 4-party clamps raised 1.2/1.1 -> 1.35/1.2 so a full
    // posse doesn't trivialize bosses (was 96-100% win on every reckoning).
    const hpF = Math.max(0.6, Math.min(1.35, 0.6 + 0.25 * (partySize - 2)));
    const dmgF = Math.max(0.8, Math.min(1.2, 0.8 + 0.1 * (partySize - 2)));
    if (hpF === 1 && dmgF === 1) return specs;
    return (specs || []).map((s) =>
      Object.assign({}, s, {
        hp: Math.max(4, Math.round(s.hp * hpF)),
        wmin: Math.max(1, Math.round(s.wmin * dmgF)),
        wmax: Math.max(2, Math.round(s.wmax * dmgF)),
      }),
    );
  };

  // ---- boot ----
  // Idempotent + scene-guarded: game.html's loader calls this once the last
  // scene script has executed; the DOMContentLoaded fallback covers any page
  // that includes the scripts as static tags. Whichever fires with the scenes
  // registered boots first; the guards prevent a premature or double boot.
  DF.boot = function () {
    if (DF._booted) return;
    if (!DF.scenes.title && !DF.scenes.battle) return; // scenes not loaded yet
    DF._booted = true;
    if (!DF.loadGame()) {
      DF.newGame();
    }
    DF.input.bind();
    DF.go(DF.scenes.title ? "title" : "battle");
  };
  window.addEventListener("DOMContentLoaded", DF.boot);
})();
