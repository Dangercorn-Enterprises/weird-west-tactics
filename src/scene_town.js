// =============================================
// DUSTFALL — TOWN SCENE (Phase 3): menu-driven hub (bible §6).
// Saloon / Outfitter / Shrine / Forge / Stables / Marshal / Doc, gold economy,
// recruitment (adds roster units), inventory. Overrides the Phase-1 stub.
// Markup: a single #tnRoot container in game.html; built via safe DOM (no innerHTML).
// =============================================
(function () {
  "use strict";
  const DF = window.DF;
  const root = () => document.querySelector('[data-scene="town"] #tnRoot');
  let curService = null,
    msg = "";

  function clear(n) {
    while (n && n.firstChild) n.removeChild(n.firstChild);
  }
  function el(tag, p, kids) {
    const e = document.createElement(tag);
    p = p || {};
    if (p.class) e.className = p.class;
    if (p.text != null) e.textContent = p.text;
    if (p.onclick) e.onclick = p.onclick;
    if (p.disabled) e.disabled = true;
    if (p.style) Object.assign(e.style, p.style);
    (kids || []).forEach((k) => k && e.appendChild(k));
    return e;
  }
  function node() {
    const n =
      typeof WORLD_NODES !== "undefined"
        ? WORLD_NODES.find((x) => x.id === DF.state.location)
        : null;
    return (
      n || {
        name: "Rustwater",
        region: "Neutral ground",
        svc: ["saloon", "outfitter", "shrine"],
        god: "coyote",
        tier: 1,
      }
    );
  }
  function god(id) {
    return typeof GODS !== "undefined" ? GODS.find((g) => g.id === id) : null;
  }
  function flash(m) {
    msg = m;
    render();
  }

  const NAMES = [
    "Eli Mourne",
    "Dolores Vane",
    "Quint Ashby",
    "Rosa Quintero",
    "Jeb Hollis",
    "Lottie Graves",
    "Amos Pike",
    "Inez Calder",
    "Wade Sumner",
    "Pearl Dukes",
    "Cyrus Flint",
    "Mae Renner",
  ];
  function genRecruit() {
    const A = typeof ARCHETYPES !== "undefined" ? ARCHETYPES : [];
    const arch = A[Math.floor(Math.random() * A.length)] || {
      id: "drifter",
      name: "Drifter",
    };
    const pg = typeof PREGEN !== "undefined" ? PREGEN[arch.id] : null;
    const name = NAMES[Math.floor(Math.random() * NAMES.length)];
    const cost = 90 + Math.floor(Math.random() * 8) * 10;
    return {
      name,
      archName: arch.name,
      cost,
      unit: {
        uid: "r" + Date.now() + Math.floor(Math.random() * 99),
        archetype: arch.id,
        name,
        stats: pg ? Object.assign({}, pg.stats) : {},
        level: 1,
        xp: 0,
        god: null,
        gear: { weapon: null, armor: null },
        hpDamage: 0,
        alive: true,
      },
    };
  }
  const RUMORS = [
    '"Forgeworks men been buyin\' up every claim east of here. Pay in brass, threaten in iron."',
    "\"Folks say the dead don't stay buried out past the Boneyard. Don't camp there.\"",
    '"There\'s a witch rides the dust storms. Gets in your head before her coyotes get your throat."',
    "\"The army hauled somethin' out of Roswell in crates. Whatever it was, it wasn't empty.\"",
    '"High ground wins fights out here. Cover keeps you breathin\'. Remember it."',
  ];
  function rumor() {
    return RUMORS[Math.floor(Math.random() * RUMORS.length)];
  }

  function render() {
    const r = root();
    if (!r) return;
    clear(r);
    const n = node();
    DF.state.inventory = DF.state.inventory || {};
    if (!curService || (n.svc || []).indexOf(curService) < 0)
      curService = (n.svc || ["saloon"])[0];
    const g = god(n.god);

    r.appendChild(
      el("div", { class: "townhead" }, [
        el("div", {
          class: "tag",
          text:
            "Gold " +
            DF.state.gold +
            "  ·  Day " +
            DF.state.day +
            (g ? "  ·  " + g.faction : ""),
        }),
        el("h1", {
          text: n.name,
          style: {
            fontFamily: "'Rye',serif",
            color: "var(--amber)",
            fontSize: "40px",
            margin: "4px 0 0",
          },
        }),
        el("div", { class: "sub", text: n.region || "" }),
      ]),
    );

    const labels = {
      saloon: "Saloon",
      outfitter: "Outfitter",
      shrine: "Shrine",
      forge: "Forge",
      stable: "Stables",
      marshal: "Marshal",
      doc: "Doc",
    };
    const tabs = el("div", {
      style: {
        display: "flex",
        gap: "8px",
        flexWrap: "wrap",
        justifyContent: "center",
        margin: "14px 0",
      },
    });
    (n.svc || ["saloon"]).forEach((s) =>
      tabs.appendChild(
        el("button", {
          class: "btn" + (curService === s ? " warn" : ""),
          text: labels[s] || s,
          style: { minWidth: "auto" },
          onclick: () => {
            curService = s;
            msg = "";
            render();
          },
        }),
      ),
    );
    r.appendChild(tabs);

    const c = el("div", {
      style: { minHeight: "200px", width: "520px", maxWidth: "90vw" },
    });
    (
      ({ saloon, outfitter, shrine, marshal, doc, forge, stable })[
        curService
      ] || saloon
    )(c, n);
    r.appendChild(c);

    if (msg)
      r.appendChild(
        el("div", {
          text: msg,
          style: {
            fontStyle: "italic",
            color: "#d4a843",
            margin: "12px 0",
            minHeight: "18px",
            textAlign: "center",
          },
        }),
      );
    r.appendChild(
      el("button", {
        class: "btn",
        text: "Depart → Map",
        onclick: () => DF.go("worldmap"),
        style: { marginTop: "10px" },
      }),
    );
  }

  function row(label, btnText, opts) {
    const o = opts || {};
    return el(
      "div",
      {
        style: {
          display: "flex",
          justifyContent: "space-between",
          alignItems: "center",
          gap: "14px",
          borderBottom: "1px solid rgba(160,82,45,.25)",
          padding: "10px 4px",
        },
      },
      [
        el("div", {
          text: label,
          style: { textAlign: "left", fontSize: "14px", color: "#cdbf9f" },
        }),
        el("button", {
          class: "btn" + (o.warn ? " warn" : ""),
          text: btnText,
          disabled: o.disabled,
          style: { minWidth: "120px" },
          onclick: o.onclick,
        }),
      ],
    );
  }

  function saloon(c) {
    c.appendChild(
      el("p", {
        class: "flavor",
        text: "Piano music, crowd noise, wanted posters on the wall. The barkeep knows everything and charges for it.",
        style: { color: "#9a8a6a", fontStyle: "italic", marginBottom: "8px" },
      }),
    );
    c.appendChild(
      row("Rest — heal the whole crew (costs 1 day)", "Rest", {
        onclick: () => {
          DF.state.party.forEach((p) => (p.hpDamage = 0));
          DF.state.day += 1;
          DF.saveGame();
          flash(
            "The crew patches up and sleeps it off. Day " + DF.state.day + ".",
          );
        },
      }),
    );
    if (!DF._recruit) DF._recruit = genRecruit();
    const rc = DF._recruit;
    const full = DF.state.party.length >= 6;
    const broke = DF.state.gold < rc.cost;
    c.appendChild(
      row(
        "Recruit — " + rc.name + ", the " + rc.archName + " (" + rc.cost + "g)",
        full ? "Roster Full" : "Hire",
        {
          warn: true,
          disabled: full || broke,
          onclick: () => {
            DF.state.gold -= rc.cost;
            DF.state.party.push(rc.unit);
            DF._recruit = genRecruit();
            DF.saveGame();
            flash(
              rc.name +
                " throws in with you. Crew: " +
                DF.state.party.length +
                ".",
            );
          },
        },
      ),
    );
    c.appendChild(
      row("Rumors — lean in close", "Listen", {
        onclick: () => flash(rumor()),
      }),
    );
  }

  // ---- Pass 5/6 (v1.1): gear equipping — bought weapons/armor finally matter ----
  function catalogOf(kind) {
    if (kind === "weapon") return typeof WEAPONS !== "undefined" ? WEAPONS : [];
    return typeof ARMOR !== "undefined" ? ARMOR : [];
  }
  function allowedFor(p, kind, it) {
    if (kind === "weapon" && it.archetype && it.archetype !== p.archetype)
      return false; // class-locked (Steam Cannon, Hex Focus)
    if (kind === "armor" && it.faction && p.god !== it.faction) return false; // god-locked (Clockwork Exo)
    return true;
  }
  function gearLabel(p, kind) {
    const id = p.gear && p.gear[kind];
    if (!id) return kind === "weapon" ? "default weapon" : "no armor";
    const it = catalogOf(kind).find((x) => x.id === id);
    if (!it) return id;
    return kind === "weapon"
      ? it.name + " (" + it.dmg[0] + "-" + it.dmg[1] + ", rng " + it.range + ")"
      : it.name +
          " (def " +
          it.def +
          (it.speed ? ", spd " + it.speed : "") +
          ")";
  }
  function cycleGear(p, kind) {
    p.gear = p.gear || { weapon: null, armor: null };
    const inv = DF.state.inventory;
    const opts = [null].concat(
      catalogOf(kind)
        .filter((it) => (inv[it.id] || 0) > 0 && allowedFor(p, kind, it))
        .map((it) => it.id),
    );
    const cur = p.gear[kind];
    const idx = opts.indexOf(cur);
    const next = opts[(idx + 1) % opts.length];
    if (next === cur) {
      flash("Nothing else " + p.name + " can wear — buy gear above.");
      return;
    }
    if (cur) inv[cur] = (inv[cur] || 0) + 1; // hand the old piece back
    if (next) inv[next] = Math.max(0, (inv[next] || 0) - 1); // take the new one
    p.gear[kind] = next;
    DF.saveGame();
    render();
  }

  function outfitter(c) {
    c.appendChild(
      el("p", {
        class: "flavor",
        text: "Guns, armor, and Ashfall charges, frontier-style. Inventory varies by town.",
        style: { color: "#9a8a6a", fontStyle: "italic", marginBottom: "8px" },
      }),
    );
    const goods = [];
    (typeof WEAPONS !== "undefined" ? WEAPONS : [])
      .slice(0, 4)
      .forEach((w) => goods.push({ k: "weapon", it: w }));
    (typeof ARMOR !== "undefined" ? ARMOR : [])
      .slice(0, 3)
      .forEach((a) => goods.push({ k: "armor", it: a }));
    (typeof CONSUMABLES !== "undefined" ? CONSUMABLES : [])
      .slice(0, 3)
      .forEach((x) => goods.push({ k: "item", it: x }));
    goods.forEach(({ k, it }) => {
      const own = DF.state.inventory[it.id] || 0;
      c.appendChild(
        row(
          it.name +
            (it.note ? " — " + it.note : "") +
            (own ? "  (owned " + own + ")" : "") +
            "  [" +
            it.cost +
            "g]",
          "Buy",
          {
            disabled: DF.state.gold < it.cost,
            onclick: () => {
              DF.state.gold -= it.cost;
              DF.state.inventory[it.id] = (DF.state.inventory[it.id] || 0) + 1;
              DF.saveGame();
              flash("Bought " + it.name + ".");
            },
          },
        ),
      );
    });
    // ---- outfit the posse: cycle each rider through owned, allowed gear ----
    c.appendChild(
      el("p", {
        text: "— OUTFIT THE POSSE —",
        style: {
          color: "#a0522d",
          letterSpacing: "3px",
          fontSize: "11px",
          textAlign: "center",
          margin: "14px 0 2px",
        },
      }),
    );
    (DF.state.party || []).forEach((p) => {
      p.gear = p.gear || { weapon: null, armor: null };
      c.appendChild(
        row(p.name + " · " + gearLabel(p, "weapon"), "Swap Gun", {
          onclick: () => cycleGear(p, "weapon"),
        }),
      );
      c.appendChild(
        row(p.name + " · " + gearLabel(p, "armor"), "Swap Armor", {
          onclick: () => cycleGear(p, "armor"),
        }),
      );
    });
  }

  function shrine(c, n) {
    const g = god(n.god);
    if (!g) {
      c.appendChild(el("p", { text: "No shrine stands here." }));
      return;
    }
    c.appendChild(
      el("p", {
        class: "flavor",
        text: g.title + " — " + g.domain + ". Corruption: " + g.corruption,
        style: { color: "#9a8a6a", fontStyle: "italic", marginBottom: "4px" },
      }),
    );
    c.appendChild(
      el("p", {
        text:
          "Favor with " +
          g.name +
          ": " +
          ((DF.state.favor && DF.state.favor[g.id]) || 0) +
          "  (fuels divine ultimates — 1 per use, empowered at 3+)",
        style: { color: "#d4a843", marginBottom: "8px", fontSize: "13px" },
      }),
    );
    c.appendChild(
      row("Pray — a blessing for your next battle", "Pray (" + "free)", {
        onclick: () => {
          DF.state.flags.blessing = g.id;
          DF.saveGame();
          flash(g.name + "'s favor settles over the crew.");
        },
      }),
    );
    DF.state.party.forEach((p) => {
      const aligned = p.god === g.id;
      c.appendChild(
        row(
          p.name +
            (p.god
              ? " — sworn to " + (god(p.god) ? god(p.god).name : p.god)
              : " — unsworn"),
          aligned ? "Aligned" : "Swear to " + g.name,
          {
            disabled: aligned,
            onclick: () => {
              p.god = g.id;
              DF.saveGame();
              flash(
                p.name +
                  " swears to " +
                  g.name +
                  ". " +
                  g.divine.name +
                  " granted.",
              );
            },
          },
        ),
      );
    });
    c.appendChild(
      row("Donate 50g — raise favor with " + g.name, "Donate", {
        disabled: DF.state.gold < 50,
        onclick: () => {
          DF.state.gold -= 50;
          DF.state.favor[g.id] = (DF.state.favor[g.id] || 0) + 1;
          DF.saveGame();
          flash("Favor with " + g.name + ": " + DF.state.favor[g.id] + ".");
        },
      }),
    );
  }

  function marshal(c, n) {
    c.appendChild(
      el("p", {
        class: "flavor",
        text: "Bounty board, reputation, the occasional posse. Law work pays in gold and grief.",
        style: { color: "#9a8a6a", fontStyle: "italic", marginBottom: "8px" },
      }),
    );
    const reward = 60 + (n.tier || 1) * 40;
    c.appendChild(
      row(
        "Bounty — clear a nest of trouble (" + reward + "g on success)",
        "Ride Out",
        {
          warn: true,
          onclick: () => {
            const pool =
              typeof ENEMY_CATALOG !== "undefined"
                ? ENEMY_CATALOG.filter(
                    (e) => e.tier <= Math.max(1, n.tier) && !e.boss,
                  )
                : [];
            const count = 2 + (n.tier || 1);
            const enemies = [];
            for (let i = 0; i < count && pool.length; i++)
              enemies.push(pool[Math.floor(Math.random() * pool.length)]);
            DF.go("battle", {
              title: "Bounty: " + n.name,
              biome: DF.biomeFor(n.god),
              enemies,
              onComplete: (res) => {
                if (res && res.win) {
                  DF.state.gold += reward;
                  DF.saveGame();
                }
                DF.go("town", {});
                curService = "marshal";
                msg =
                  res && res.win
                    ? "Bounty paid: +" + reward + "g."
                    : "The bounty got away. Patch up and try again.";
              },
            });
          },
        },
      ),
    );
  }

  function doc(c) {
    c.appendChild(
      el("p", {
        class: "flavor",
        text: "Medicine beyond battlefield bandages — for a price.",
        style: { color: "#9a8a6a", fontStyle: "italic", marginBottom: "8px" },
      }),
    );
    c.appendChild(
      row("Full heal + tend wounds (40g)", "Treat", {
        disabled: DF.state.gold < 40,
        onclick: () => {
          DF.state.gold -= 40;
          DF.state.party.forEach((p) => (p.hpDamage = 0));
          DF.saveGame();
          flash("The crew is mended, good as the frontier allows.");
        },
      }),
    );
  }
  function forge(c) {
    c.appendChild(
      el("p", {
        class: "flavor",
        text: "Hammered brass, Ashfall fire, the smell of hot iron. Weapon mods + prosthetics deepen in a later pass.",
        style: { color: "#9a8a6a", fontStyle: "italic" },
      }),
    );
  }
  function stable(c) {
    c.appendChild(
      el("p", {
        class: "flavor",
        text: "Horses, camels, and one clockwork steed that hisses steam. Mounts cut travel time — coming in a later pass.",
        style: { color: "#9a8a6a", fontStyle: "italic" },
      }),
    );
  }

  DF.register("town", {
    enter(params) {
      if (params && params.node)
        DF.state.location = params.node.id || DF.state.location;
      msg = "";
      render();
    },
    exit() {},
  });
  DF.townDebug = {
    node,
    genRecruit,
    render,
    set service(s) {
      curService = s;
    },
  };
})();
