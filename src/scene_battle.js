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
    host.querySelector("#babilityBtn").onclick = toggleAbility;
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
    return o;
  }

  function partyToUnit(p, i) {
    const arch =
      typeof ARCHETYPES !== "undefined"
        ? ARCHETYPES.find((a) => a.id === p.archetype)
        : null;
    const w =
      arch && arch.weapons && arch.weapons[0]
        ? arch.weapons[0]
        : { damage: [4, 8], range: 5, accuracy: 72 };
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
    const ability = ABIL[p.archetype] || "Aimed Shot";
    return mkUnit({
      id: p.uid || "p" + i,
      name: p.name || (arch ? arch.name : "Rider"),
      role: arch ? arch.name : "Rider",
      side: "p",
      q: 1,
      r: [1, 4, 7, 2][i] || 1,
      hp: 10 + vigor * 2 - (p.hpDamage || 0),
      str,
      quick,
      aim: w.accuracy + (deft - 5) * 2,
      rng: w.range,
      wmin: w.damage[0],
      wmax: w.damage[1],
      color: archColor(p.archetype),
      ability,
    });
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
    return mkUnit({
      id: "e" + i,
      name: spec.name,
      role: spec.faction || "",
      side: "e",
      q: 8,
      r: 1,
      color: spec.color || "#c0392b",
      hp: spec.hp,
      str: spec.str,
      quick: spec.quick,
      aim: spec.aim,
      rng: spec.rng,
      wmin: spec.wmin,
      wmax: spec.wmax,
      hexer: beh === "hexer",
      blinker: beh === "teleport",
      bomber: beh === "bomber",
      tier: spec.tier,
      boss: spec.boss,
    });
  }

  // ---- grid setup ----
  function buildGrid() {
    grid = [];
    for (let r = 0; r < ROWS; r++) {
      grid.push([]);
      for (let q = 0; q < COLS; q++)
        grid[r].push({ h: 0, cover: 0, deco: null });
    }
    const set = (q, r, o) => Object.assign(grid[r][q], o);
    [
      [3, 2],
      [6, 7],
      [2, 6],
      [7, 3],
    ].forEach(([q, r]) => set(q, r, { h: 1, deco: "mesa" }));
    [
      [4, 4],
      [5, 5],
    ].forEach(([q, r]) => set(q, r, { h: 2, deco: "mesa" }));
    [
      [2, 3],
      [7, 6],
      [4, 7],
      [5, 2],
      [1, 5],
      [8, 4],
    ].forEach(([q, r]) => set(q, r, { cover: 0.4, deco: "crate" }));
    [
      [3, 5],
      [6, 4],
      [2, 8],
      [7, 8],
      [4, 1],
      [5, 8],
    ].forEach(([q, r]) => set(q, r, { cover: 0.2, deco: "cactus" }));
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
      ab.disabled = !(sel && sel.ability && sel.ap >= 2 && sel.side === "p");
      ab.textContent = sel && sel.ability ? sel.ability : "Ability";
    }
    renderParty();
  }

  function moveTo(u, q, r, cb) {
    const cost = reach(u)[q + "," + r];
    if (cost === undefined) return;
    busy = true;
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
        u.px = u.py = undefined;
        u.q = q;
        u.r = r;
        u.ap -= cost;
        busy = false;
        refreshSel();
        cb && cb();
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
        const dmg = Math.round(rollDmg(att) * (opts.mult || 1));
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
        if (att.hexer && def.side === "p" && def.alive) {
          def.jinx = 1;
          floaters.push({
            x: tgt.x,
            y: tgt.y - 56,
            t: "JINXED",
            life: 42,
            c: "#9a6ab8",
          });
          log(def.name + " is jinxed — aim suffers.");
        }
        if (def.hp <= 0) {
          def.alive = false;
          def.downed = 1;
          if (def.side === "e") kills++;
          log(def.name + " falls.");
        }
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
  function blast(att, def, cb) {
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
      caught.forEach((u) => {
        const dmg = Math.floor(Math.random() * 4) + 4;
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
        }
      });
      log(att.name + "'s dynamite catches " + caught.length + " in the blast!");
      busy = false;
      refreshSel();
      checkEnd();
      cb && cb();
    }, 300);
  }

  function enemyTurn() {
    const queue = enemies.filter((e) => e.alive);
    let idx = 0;
    const step = () => {
      if (!active) return;
      if (idx >= queue.length) {
        endEnemy();
        return;
      }
      const e = queue[idx];
      e.ap = e.maxAp;
      const act = () => {
        if (!active) return;
        const tgt = players
          .filter((p) => p.alive)
          .sort((a, b) => dist(e, a) - dist(e, b))[0];
        if (!tgt) {
          idx++;
          setTimeout(step, 150);
          return;
        }
        if (dist(e, tgt) <= e.rng + 1 && e.ap >= 2) {
          e.ap -= 2;
          sel = e;
          if (e.bomber) {
            blast(e, tgt, () => setTimeout(act, 180));
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
        let best = null,
          bd = dist(e, tgt);
        Object.keys(rc).forEach((k) => {
          const [q, r] = k.split(",").map(Number);
          const d = Math.abs(q - tgt.q) + Math.abs(r - tgt.r);
          if (d < bd) {
            bd = d;
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
      if (p.alive) p.ap = p.maxAp;
    });
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
      refreshSel();
      return;
    }
    if (occ && occ.side === "e" && occ.alive && sel) {
      if (abilityMode) {
        doAbility(occ);
        return;
      }
      if (dist(sel, occ) <= sel.rng + 1 && sel.ap >= 2) {
        sel.ap -= 2;
        fire(sel, occ);
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
    players.forEach((p) => (p.jinx = 0));
    log("Enemies stir...");
    enemyTurn();
  }
  function toggleAbility() {
    if (!(sel && sel.ability && sel.ap >= 2)) return;
    if (isHeal(sel.ability)) {
      const allies = players.filter((p) => p.alive);
      const who =
        allies.slice().sort((a, b) => a.hp / a.maxHp - b.hp / b.maxHp)[0] ||
        sel;
      doAbility(who);
      return;
    }
    abilityMode = !abilityMode;
    log(abilityMode ? sel.ability + ": pick a target" : "cancelled");
  }
  function isHeal(a) {
    return a === "Lay on Hands" || a === "Soul Drain";
  }
  function doAbility(tgt) {
    abilityMode = false;
    const a = sel.ability;
    if (a === "Fan the Hammer") {
      sel.ap -= 3;
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
      log("Hex Bolt ignores cover!");
      fire(sel, tgt, { ignoreCover: true });
    } else if (a === "Ashfall Grenade") {
      sel.ap -= 2;
      log(sel.name + " lobs an Ashfall grenade!");
      blast(sel, tgt);
    } else if (a === "Called Shot") {
      sel.ap -= 3;
      log("Called Shot — dead to rights.");
      const sv = sel.aim;
      sel.aim = 999;
      fire(sel, tgt, {
        cb: () => {
          sel.aim = sv;
        },
      });
    } else if (a === "Lay on Hands" || a === "Soul Drain") {
      sel.ap -= 2;
      const amt = 6 + Math.floor(Math.random() * 5);
      const who = a === "Soul Drain" ? sel : tgt;
      if (who.downed) {
        who.alive = true;
        who.downed = false;
        who.bleed = 0;
        who.hp = amt;
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
    } else {
      sel.ap -= 2;
      fire(sel, tgt, { mult: 1.5 });
    }
  }

  function tileColor(cell) {
    return cell.h === 2 ? "#5a4428" : cell.h === 1 ? "#4a3820" : "#3a2c18";
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
    X.fillStyle = flash ? "#fff" : u.color;
    X.beginPath();
    X.moveTo(p.x, p.y + TH / 2 - 34 + bob);
    X.lineTo(p.x - 11, p.y + TH / 2 + bob);
    X.lineTo(p.x + 11, p.y + TH / 2 + bob);
    X.closePath();
    X.fill();
    X.beginPath();
    X.arc(p.x, p.y + TH / 2 - 38 + bob, 6, 0, 7);
    X.fill();
    X.fillStyle = flash ? "#fff" : "#2a1d0f";
    X.fillRect(p.x - 10, p.y + TH / 2 - 43 + bob, 20, 3);
    X.fillRect(p.x - 5, p.y + TH / 2 - 49 + bob, 10, 7);
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
    X.restore();
    requestAnimationFrame(frame);
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
      el.appendChild(card);
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
      const specs =
        params.enemies && params.enemies.length
          ? params.enemies
          : typeof ENEMY_CATALOG !== "undefined"
            ? [ENEMY_CATALOG[0], ENEMY_CATALOG[0], ENEMY_CATALOG[1]]
            : [];
      buildGrid();
      const free = SPAWNS.slice();
      enemies = specs.map((spec, i) => {
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
  };
})();
