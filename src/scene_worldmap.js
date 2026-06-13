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

  function travel(from, to) {
    const days = travelTime(from, to),
      risk = riskOf(from, to);
    DF.state.day += days;
    DF.state.location = to.id;
    DF.state.visited[to.id] = true;
    DF.saveGame();
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
        enemies: [boss].concat(minions).filter(Boolean),
        onComplete: () => DF.go("worldmap"),
      });
      return;
    }
    const chance = risk >= 3 ? 0.6 : risk === 2 ? 0.3 : 0;
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
    if (gold)
      gold.textContent = "Gold " + DF.state.gold + "  ·  Day " + DF.state.day;
    const nm = $("wcName");
    if (nm) nm.textContent = cur.name;
    const lr = $("wcLore");
    if (lr) lr.textContent = cur.lore;
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
