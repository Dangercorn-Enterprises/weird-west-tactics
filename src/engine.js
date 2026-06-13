// =============================================
// DUSTFALL ENGINE — scene manager, state, storage, scaling, input
// Classic script (no ES modules) so it runs from file://, a dev server, AND Electron.
// =============================================
(function () {
  "use strict";
  const DF = (window.DF = window.DF || {});

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
      favor: {}, // god id -> favor
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

  // ---- boot ----
  DF.boot = function () {
    if (!DF.loadGame()) {
      DF.newGame();
    }
    DF.input.bind();
    DF.go(DF.scenes.title ? "title" : "battle");
  };
  window.addEventListener("DOMContentLoaded", DF.boot);
})();
