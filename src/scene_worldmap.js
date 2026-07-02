// =============================================
// DUSTFALL — WORLDMAP SCENE (Phase 2): navigable US-Southwest parchment map.
// Overrides the Phase-1 stub (loads after scenes_hub.js). Markup in game.html (#scene-worldmap).
// =============================================
(function () {
  "use strict";
  const DF = window.DF;
  const W = 960,
    H = 600,
    PAD = 54;
  let C,
    X,
    fit,
    built = false,
    raf = false;
  let nodes,
    edges,
    adj,
    bounds,
    hover = null;

  function godColor(id) {
    const g =
      typeof GODS !== "undefined" ? GODS.find((x) => x.id === id) : null;
    return g ? g.color : "#9a8a6a";
  }
  const $ = (id) => document.querySelector('[data-scene="worldmap"] #' + id);

  // ---- Act 1 campaign spine: Catalina -> Los Angeles -> Death Valley (the Deacon) ----
  const ACT1_OBJ = [
    "Act I — Make for Los Angeles. The Deacon's revenants raid the coast.",
    "Act I — Into the Boneyard. Hunt the Deacon at Death Valley.",
    "Act I complete — the Deacon is broken. The frontier lies open.",
  ];
  function act1Step() {
    return (DF.state && DF.state.act1 && DF.state.act1.step) || 0;
  }
  function enemiesByIds(ids) {
    const cat = typeof ENEMY_CATALOG !== "undefined" ? ENEMY_CATALOG : [];
    return ids.map((id) => cat.find((e) => e.id === id)).filter(Boolean);
  }
  // Returns true if a story beat fired (and a battle was launched).
  function act1Beat(to) {
    const step = act1Step();
    DF.state.flags = DF.state.flags || {};
    // Beat 1: Los Angeles — the Revenant Vanguard. Advances only on a win.
    if (to.id === "losangeles" && step === 0) {
      DF.go("battle", {
        // balance 2026-07-01: dropped one walkin_dead — the campaign's first
        // story fight sat at 66% for the starter duo (target 70-85%).
        title: "The Revenant Vanguard",
        biome: "boneyard",
        enemies: enemiesByIds([
          "revenant_gun",
          "walkin_dead",
          "dynamite_bandit",
          "dynamite_bandit",
        ]),
        onComplete: (r) => {
          if (r && r.win) {
            DF.state.act1 = { step: 1 };
            DF.saveGame();
          }
          DF.go("worldmap");
        },
      });
      return true;
    }
    // Beat 2: Death Valley — the Deacon. Triggers once the Vanguard is won.
    if (to.id === "deathvalley" && step === 1) {
      DF.state.flags["boss_deathvalley"] = true; // suppress the generic reckoning here
      DF.saveGame();
      DF.go("battle", {
        title: "The Deacon's Reckoning",
        biome: "boneyard",
        enemies: enemiesByIds([
          "the_deacon",
          "walkin_dead",
          "walkin_dead",
          "coyote_beast",
        ]),
        onComplete: (r) => {
          if (r && r.win) {
            DF.state.act1 = { step: 2 };
            DF.state.flags.act1_deacon = true;
            DF.saveGame();
          }
          DF.go("worldmap");
        },
      });
      return true;
    }
    return false;
  }

  // ---- Act 2: the Forgeworks / Vulcan -> the Iron Foreman at Los Alamos ----
  const ACT2_OBJ = [
    "Act II — The Forgeworks rise from the ash. Make for Los Alamos.",
    "Act II — Storm the foundry. Break the Iron Foreman.",
    "Act II complete — the Foreman is scrap. Something older stirs beneath the dust.",
  ];
  // ---- Act 3: the Hollow Court / the Sleeper -> the Hollow Man (finale) ----
  const ACT3_OBJ = [
    "Act III — The Hollow Court wakes. Make for Groom Lake.",
    "Act III — End it. Face the Hollow Man before the Sleeper rises.",
    "The frontier is saved — for now.",
  ];
  function act2Active() {
    return act1Step() >= 2;
  }
  function act2Step() {
    return (DF.state && DF.state.act2 && DF.state.act2.step) || 0;
  }
  function act3Active() {
    return act2Step() >= 2;
  }
  function act3Step() {
    return (DF.state && DF.state.act3 && DF.state.act3.step) || 0;
  }
  function currentObjective() {
    if (act3Active()) return ACT3_OBJ[act3Step()] || "";
    if (act2Active()) return ACT2_OBJ[act2Step()] || "";
    return ACT1_OBJ[act1Step()] || "";
  }
  function act2Beat(to) {
    if (!act2Active() || act2Step() >= 2) return false;
    DF.state.flags = DF.state.flags || {};
    const step = act2Step();
    // Beat 1: the first leg into Act II — a Forgeworks vanguard intercepts you.
    if (step === 0) {
      DF.go("battle", {
        title: "The Forgeworks Vanguard",
        biome: "foundry",
        enemies: enemiesByIds([
          "forge_sentry",
          "forge_sentry",
          "ashfall_golem",
          "dynamite_bandit",
        ]),
        onComplete: (r) => {
          if (r && r.win) {
            DF.state.act2 = { step: 1 };
            DF.saveGame();
          }
          DF.go("worldmap");
        },
      });
      return true;
    }
    // Beat 2: reach Los Alamos -> the Iron Foreman.
    if (step === 1 && to.id === "losalamos") {
      DF.state.flags["boss_losalamos"] = true; // suppress the generic reckoning here
      DF.saveGame();
      DF.go("battle", {
        title: "The Iron Foreman",
        biome: "foundry",
        enemies: enemiesByIds([
          "iron_foreman",
          "ashfall_golem",
          "forge_sentry",
        ]),
        onComplete: (r) => {
          if (r && r.win) {
            DF.state.act2 = { step: 2 };
            DF.state.flags.act2_foreman = true;
            DF.saveGame();
          }
          DF.go("worldmap");
        },
      });
      return true;
    }
    return false;
  }
  function act3Beat(to) {
    if (!act3Active() || act3Step() >= 2) return false;
    DF.state.flags = DF.state.flags || {};
    const step = act3Step();
    // Beat 1: the Hollow Court's heralds (the Weaver) ambush the approach.
    if (step === 0) {
      DF.go("battle", {
        title: "Heralds of the Hollow Court",
        biome: "canyon",
        enemies: enemiesByIds(["the_weaver", "dust_witch", "revenant_gun"]),
        onComplete: (r) => {
          if (r && r.win) {
            DF.state.act3 = { step: 1 };
            DF.saveGame();
          }
          DF.go("worldmap");
        },
      });
      return true;
    }
    // Beat 2 (finale): reach Groom Lake -> the Hollow Man -> the ending.
    if (step === 1 && to.id === "area51") {
      DF.state.flags["boss_area51"] = true; // suppress the generic reckoning here
      DF.saveGame();
      DF.go("battle", {
        title: "The Hollow Man",
        biome: "hollow",
        enemies: enemiesByIds(["hollow_man", "coyotes_shadow", "dust_devil"]),
        onComplete: (r) => {
          if (r && r.win) {
            DF.state.act3 = { step: 2 };
            DF.state.flags.act3_hollow = true;
            DF.state.flags.campaign_complete = true;
            DF.saveGame();
            DF.go(DF.scenes.ending ? "ending" : "worldmap", { win: true });
          } else {
            DF.go("worldmap"); // the Hollow Man stands — regroup and return
          }
        },
      });
      return true;
    }
    return false;
  }

  function build() {
    const host = document.querySelector('[data-scene="worldmap"]');
    C = host.querySelector("#wc");
    X = C.getContext("2d");
    fit = DF.fitCanvas(C, W, H);
    nodes = typeof WORLD_NODES !== "undefined" ? WORLD_NODES : [];
    edges = typeof WORLD_EDGES !== "undefined" ? WORLD_EDGES : [];
    // fit node coords to the canvas
    const xs = nodes.map((n) => n.x),
      ys = nodes.map((n) => n.y);
    bounds = {
      x0: Math.min(...xs),
      x1: Math.max(...xs),
      y0: Math.min(...ys),
      y1: Math.max(...ys),
    };
    nodes.forEach((n) => {
      n.px =
        PAD + ((n.x - bounds.x0) / (bounds.x1 - bounds.x0)) * (W - 2 * PAD);
      n.py =
        PAD + ((n.y - bounds.y0) / (bounds.y1 - bounds.y0)) * (H - 2 * PAD);
    });
    adj = {};
    nodes.forEach((n) => (adj[n.id] = []));
    edges.forEach(([a, b]) => {
      if (adj[a] && adj[b]) {
        adj[a].push(b);
        adj[b].push(a);
      }
    });
    C.addEventListener("mousemove", (e) => {
      const p = fit.toLocal(e.clientX, e.clientY);
      hover = nodeAt(p.x, p.y);
    });
    C.addEventListener("click", onClick);
    host.querySelector("#wcEnter").onclick = () => {
      DF.go("town", { node: current() });
    };
    host.querySelector("#wcTitle").onclick = () => DF.go("title");
    built = true;
  }

  function current() {
    return (
      nodes.find((n) => n.id === DF.state.location) ||
      nodes.find((n) => n.start) ||
      nodes[0]
    );
  }
  function node(id) {
    return nodes.find((n) => n.id === id);
  }
  function nodeAt(mx, my) {
    let best = null,
      bd = 22 * 22;
    nodes.forEach((n) => {
      const d = (mx - n.px) * (mx - n.px) + (my - n.py) * (my - n.py);
      if (d < bd) {
        bd = d;
        best = n;
      }
    });
    return best;
  }
  function travelTime(a, b) {
    const dx = a.x - b.x,
      dy = a.y - b.y;
    return Math.max(1, Math.round(Math.sqrt(dx * dx + dy * dy) * 22));
  }
  function riskOf(a, b) {
    const e = edges.find(
      ([x, y]) => (x === a.id && y === b.id) || (x === b.id && y === a.id),
    );
    return e ? e[2] : 2;
  }

  function onClick(e) {
    const p = fit.toLocal(e.clientX, e.clientY);
    const n = nodeAt(p.x, p.y);
    if (!n) return;
    const cur = current();
    if (n.id === cur.id) {
      DF.go("town", { node: cur });
      return;
    }
    if (adj[cur.id] && adj[cur.id].indexOf(n.id) >= 0) {
      travel(cur, n);
    }
  }

  function mount() {
    return typeof MOUNTS !== "undefined"
      ? MOUNTS.find((m) => m.id === DF.state.mount)
      : null;
  }
  function travel(from, to) {
    // Pass 16 (v1.1): a mount team cuts travel days and ambush odds
    const mt = mount();
    const days = Math.max(
      1,
      Math.round(travelTime(from, to) * (mt ? mt.travelF : 1)),
    );
    const risk = riskOf(from, to);
    DF.state.day += days;
    DF.state.location = to.id;
    DF.state.visited[to.id] = true;
    DF.saveGame();
    // Act 1 story beats take precedence over generic encounters
    if (act1Beat(to)) return;
    if (act2Beat(to)) return;
    if (act3Beat(to)) return;
    const ENC = typeof ENEMY_CATALOG !== "undefined" ? ENEMY_CATALOG : [];
    // first arrival at a tier-3 node = a boss reckoning
    if (to.tier >= 3 && !DF.state.flags["boss_" + to.id]) {
      DF.state.flags["boss_" + to.id] = true;
      DF.saveGame();
      const boss =
        ENC.find((e) => e.boss && e.faction === to.god) ||
        ENC.find((e) => e.boss);
      const minions = ENC.filter((e) => e.tier <= 2 && !e.boss).slice(0, 2);
      DF.go("battle", {
        title: "Reckoning at " + to.name,
        biome: DF.biomeFor(to.god),
        enemies: [boss].concat(minions).filter(Boolean),
        onComplete: () => DF.go("worldmap"),
      });
      return;
    }
    let chance = risk >= 3 ? 0.6 : risk === 2 ? 0.3 : 0;
    if (mt && chance > 0) chance = Math.max(0.05, chance + mt.ambushMod); // outrun trouble
    if (Math.random() < chance) {
      // ambush on the trail — enemies scaled to the destination's tier
      const pool =
        typeof ENEMY_CATALOG !== "undefined"
          ? ENEMY_CATALOG.filter(
              (en) => en.tier <= Math.max(1, to.tier) && !en.boss,
            )
          : [];
      const count = 2 + Math.floor(Math.random() * 2) + (to.tier > 1 ? 1 : 0);
      const enemies = [];
      for (let i = 0; i < count && pool.length; i++)
        enemies.push(pool[Math.floor(Math.random() * pool.length)]);
      DF.go("battle", {
        title: "Ambush on the " + (risk === 3 ? "wilderness" : "trail"),
        biome: DF.biomeFor(to.god),
        enemies,
        onComplete: () => DF.go("worldmap"),
      });
    } else {
      render();
    }
  }

  function render() {
    if (!built) return;
    // parchment
    const g = X.createRadialGradient(
      W / 2,
      H * 0.4,
      80,
      W / 2,
      H * 0.4,
      W * 0.7,
    );
    g.addColorStop(0, "#d8c8a4");
    g.addColorStop(1, "#b49b6f");
    X.fillStyle = g;
    X.fillRect(0, 0, W, H);
    // faint vignette + edge burn
    X.fillStyle = "rgba(60,40,18,0.10)";
    for (let i = 0; i < 3; i++) {
      X.fillRect(0, 0, W, 14 + i * 8);
      X.fillRect(0, H - 14 - i * 8, W, 14 + i * 8);
      X.fillRect(0, 0, 14 + i * 8, H);
      X.fillRect(W - 14 - i * 8, 0, 14 + i * 8, H);
    }
    // divine-zone tint blobs behind nodes
    nodes.forEach((n) => {
      const rg = X.createRadialGradient(n.px, n.py, 2, n.px, n.py, 64);
      rg.addColorStop(0, godColor(n.god) + "33");
      rg.addColorStop(1, "rgba(0,0,0,0)");
      X.fillStyle = rg;
      X.beginPath();
      X.arc(n.px, n.py, 64, 0, 7);
      X.fill();
    });
    // paths
    const cur = current();
    edges.forEach(([a, b, risk]) => {
      const na = node(a),
        nb = node(b);
      if (!na || !nb) return;
      X.strokeStyle =
        risk >= 3
          ? "rgba(120,40,20,0.5)"
          : risk === 2
            ? "rgba(90,60,30,0.55)"
            : "rgba(60,45,25,0.7)";
      X.lineWidth = risk === 1 ? 2.5 : risk === 2 ? 2 : 1.5;
      X.setLineDash(risk >= 3 ? [4, 5] : risk === 2 ? [8, 5] : []);
      X.beginPath();
      X.moveTo(na.px, na.py);
      X.lineTo(nb.px, nb.py);
      X.stroke();
      X.setLineDash([]);
    });
    // nodes
    nodes.forEach((n) => {
      const reachable = adj[cur.id] && adj[cur.id].indexOf(n.id) >= 0;
      const r = n.id === cur.id ? 11 : 8;
      X.beginPath();
      X.arc(n.px, n.py, r + 3, 0, 7);
      X.fillStyle = "#2a1d0f";
      X.fill();
      X.beginPath();
      X.arc(n.px, n.py, r, 0, 7);
      X.fillStyle = godColor(n.god);
      X.fill();
      X.strokeStyle =
        n.id === cur.id ? "#fff" : reachable ? "#f4e7c8" : "#2a1d0f";
      X.lineWidth = n.id === cur.id ? 2.5 : reachable ? 2 : 1;
      X.stroke();
      if (hover && hover.id === n.id) {
        X.beginPath();
        X.arc(n.px, n.py, r + 6, 0, 7);
        X.strokeStyle = "#d4a843";
        X.lineWidth = 1.5;
        X.stroke();
      }
      // label
      X.font = "12px 'Special Elite', monospace";
      X.textAlign = "center";
      X.fillStyle = "#2a1d0f";
      X.fillText(n.name, n.px, n.py - r - 6);
    });
    // player token at current
    const t = Date.now() / 300;
    const yy = cur.py + Math.sin(t) * 2;
    X.fillStyle = "#1a1209";
    X.beginPath();
    X.ellipse(cur.px, cur.py + 13, 9, 4, 0, 0, 7);
    X.fill();
    X.fillStyle = "#e8d5a3";
    X.beginPath();
    X.moveTo(cur.px, yy - 20);
    X.lineTo(cur.px - 7, yy - 2);
    X.lineTo(cur.px + 7, yy - 2);
    X.closePath();
    X.fill();
    X.beginPath();
    X.arc(cur.px, yy - 23, 4, 0, 7);
    X.fill();
    // HUD text
    const gold = $("wcGold");
    if (gold) {
      const mt = mount();
      gold.textContent =
        "Gold " +
        DF.state.gold +
        "  ·  Day " +
        DF.state.day +
        (mt ? "  ·  " + mt.name : "");
    }
    const nm = $("wcName");
    if (nm) nm.textContent = cur.name;
    const lr = $("wcLore");
    if (lr) lr.textContent = cur.lore;
    const ob = $("wcObjective");
    if (ob) ob.textContent = currentObjective();
  }

  function loop() {
    if (!raf) return;
    render();
    requestAnimationFrame(loop);
  }

  DF.register("worldmap", {
    enter() {
      if (!built) build();
      if (!DF.state.location || !node(DF.state.location)) {
        const s = nodes.find((n) => n.start) || nodes[0];
        DF.state.location = s.id;
        DF.state.visited[s.id] = true;
      }
      // set the objective synchronously so it shows without waiting on a frame
      const ob = $("wcObjective");
      if (ob) ob.textContent = currentObjective();
      raf = true;
      requestAnimationFrame(loop);
    },
    exit() {
      raf = false;
    },
  });

  DF.world = {
    get nodes() {
      return nodes;
    },
    get adj() {
      return adj;
    },
    current,
    travel,
    node,
  };
})();
