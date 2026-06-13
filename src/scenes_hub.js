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
        DF.newGame();
        DF.state.party = DF.makeStarterParty();
        DF.saveGame();
        DF.go("worldmap");
      };
      h.querySelector("#tSkirmish").onclick = () => {
        if (!DF.state.party || !DF.state.party.length)
          DF.state.party = DF.makeStarterParty();
        DF.go("battle", { title: "Skirmish at the Crossing" });
      };
      const cont = h.querySelector("#tContinue");
      cont.style.display = DF.hasSave() ? "" : "none";
      cont.onclick = () => {
        DF.loadGame();
        DF.go("worldmap");
      };
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
