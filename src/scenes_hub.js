// =============================================
// DUSTFALL — hub scenes: title + results (full), worldmap + town (Phase 1 stubs).
// Worldmap is replaced in Phase 2, Town in Phase 3. Markup is static in game.html.
// =============================================
(function () {
  "use strict";
  const DF = window.DF;
  const host = (name) => document.querySelector('[data-scene="' + name + '"]');

  // ---- TITLE ----
  DF.register("title", {
    enter() {
      const h = host("title");
      h.querySelector("#tNew").onclick = () => {
        DF.go("creator");
      };
      h.querySelector("#tSkirmish").onclick = () => {
        if (!DF.state.party || !DF.state.party.length)
          DF.state.party = DF.makeStarterParty();
        DF.go("battle", { title: "Skirmish at the Crossing" });
      };
      h.querySelector("#tBoss").onclick = () => {
        if (!DF.state.party || !DF.state.party.length)
          DF.state.party = DF.makeStarterParty();
        const cat = typeof ENEMY_CATALOG !== "undefined" ? ENEMY_CATALOG : [];
        const deacon = cat.find((e) => e.id === "the_deacon");
        const minions = cat.length ? [cat[0], cat[0], cat[2]] : [];
        DF.go("battle", {
          title: "The Deacon's Reckoning",
          enemies: deacon ? [deacon].concat(minions) : minions,
        });
      };
      const cont = h.querySelector("#tContinue");
      cont.style.display = DF.hasSave() ? "" : "none";
      cont.onclick = () => {
        DF.loadGame();
        DF.go("worldmap");
      };
    },
  });

  // ---- CHARACTER CREATOR (New Game flow) ----
  DF.register("creator", {
    enter() {
      const h = host("creator");
      const archs = typeof ARCHETYPES !== "undefined" ? ARCHETYPES : [];
      const wrap = h.querySelector("#ccArch");
      const nameIn = h.querySelector("#ccName");
      const detail = h.querySelector("#ccDetail");
      let selId = archs.length ? archs[0].id : null;
      const pregenName = (id) =>
        typeof PREGEN !== "undefined" && PREGEN[id] ? PREGEN[id].name : "";
      const archOf = (id) => archs.find((a) => a.id === id);

      function paintDetail() {
        const a = archOf(selId);
        detail.textContent = a ? a.desc + "  " + (a.lore || "") : "";
      }
      function paintSel() {
        [...wrap.children].forEach((c) =>
          c.classList.toggle("sel", c.dataset.id === selId),
        );
      }
      function buildCards() {
        while (wrap.firstChild) wrap.removeChild(wrap.firstChild);
        archs.forEach((a) => {
          const card = document.createElement("div");
          card.className = "cc-card" + (a.id === selId ? " sel" : "");
          card.dataset.id = a.id;
          const ic = document.createElement("div");
          ic.className = "cc-ic";
          ic.textContent = a.icon || "•";
          const nm = document.createElement("div");
          nm.className = "cc-nm";
          nm.textContent = a.name;
          const bo = document.createElement("div");
          bo.className = "cc-bo";
          bo.textContent = a.bonuses || "";
          card.appendChild(ic);
          card.appendChild(nm);
          card.appendChild(bo);
          card.onclick = () => {
            selId = a.id;
            nameIn.value = pregenName(a.id);
            paintSel();
            paintDetail();
          };
          wrap.appendChild(card);
        });
      }
      function mkMember(id, uid, nm) {
        const pg = typeof PREGEN !== "undefined" ? PREGEN[id] : null;
        const arch = archOf(id);
        return {
          uid,
          archetype: id,
          name: nm || (pg ? pg.name : arch ? arch.name : "Rider"),
          stats: pg ? Object.assign({}, pg.stats) : {},
          level: 1,
          xp: 0,
          god: null,
          gear: { weapon: null, armor: null },
          hpDamage: 0,
          alive: true,
        };
      }

      buildCards();
      nameIn.value = pregenName(selId);
      paintDetail();

      h.querySelector("#ccBegin").onclick = () => {
        DF.newGame();
        const nm = (nameIn.value || "").trim() || pregenName(selId);
        const compId = selId === "gunslinger" ? "hexslinger" : "gunslinger";
        DF.state.party = [mkMember(selId, "p0", nm), mkMember(compId, "p1")];
        DF.saveGame();
        DF.go("worldmap");
      };
      h.querySelector("#ccBack").onclick = () => DF.go("title");
    },
  });

  // ---- RESULTS ----
  DF.register("results", {
    enter(r) {
      const h = host("results");
      const win = r && r.win;
      h.querySelector("#rTitle").textContent = win
        ? "The Dust Settles"
        : "Wiped Out";
      h.querySelector("#rTitle").style.color = win ? "#d4a843" : "#c0392b";
      h.querySelector("#rBody").textContent = r
        ? r.kills + " kills · " + r.turns + " turns · +" + r.xp + " XP earned"
        : "";
      // award XP to the surviving roster and process level-ups (Phase 5)
      if (r && r.xp && DF.state && DF.state.party && DF.state.party.length) {
        const share = Math.round(r.xp / DF.state.party.length);
        const ups = [];
        DF.state.party.forEach((p) => {
          if (p.alive !== false) {
            const reached = DF.gainXP(p, share);
            if (reached.length) ups.push(p.name + " → Lv " + p.level);
          }
        });
        DF.saveGame();
        if (ups.length) {
          const body = h.querySelector("#rBody");
          body.textContent =
            body.textContent + "  ·  LEVEL UP — " + ups.join(", ");
        }
      }
      h.querySelector("#rContinue").onclick = () => {
        DF.go(DF.scenes.worldmap ? "worldmap" : "title");
      };
    },
  });

  // ---- WORLDMAP (Phase 1 stub — Phase 2 builds the real Southwest map) ----
  DF.register("worldmap", {
    enter() {
      const h = host("worldmap");
      const g = h.querySelector("#wmGold");
      if (g)
        g.textContent =
          "Gold: " +
          (DF.state ? DF.state.gold : 0) +
          "  ·  Day " +
          (DF.state ? DF.state.day : 1);
      h.querySelector("#wmTown").onclick = () => DF.go("town", {});
      h.querySelector("#wmBattle").onclick = () =>
        DF.go("battle", { title: "Random Encounter" });
      h.querySelector("#wmTitle2").onclick = () => DF.go("title");
    },
  });

  // ---- TOWN (Phase 1 stub — Phase 3 builds the hub) ----
  DF.register("town", {
    enter() {
      const h = host("town");
      h.querySelector("#tnBack").onclick = () => DF.go("worldmap");
      h.querySelector("#tnBattle").onclick = () =>
        DF.go("battle", { title: "Defense of the Town" });
    },
  });
})();
