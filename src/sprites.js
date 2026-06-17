// =============================================
// DUSTFALL — 16-bit pixel sprite system (REAL sprites, not primitives)
// Hand-authored pixel data + palette + renderer. Self-contained, ships in the package.
// Seeded 2026-06-16 with 3 approved sprites; OVERNIGHT goal extends to the full roster.
// RULE: every sprite added here MUST be screenshot-verified in-browser before being called done.
// =============================================

// Ashlands palette (from DUSTFALL_BIBLE §2). One char per pixel; '.'/' ' = transparent.
const SPRITE_PAL = {
  K: "#3a2814", // hat / dark brown
  L: "#6b4226", // duster leather
  l: "#936037", // leather highlight
  S: "#e8c8a0", // skin
  d: "#c4956a", // skin shadow
  D: "#4a6080", // denim shirt/pants
  G: "#8899aa", // gun steel
  B: "#d4a843", // brass
  b: "#120c05", // outline / boots (near-black)
  g: "#7c9a6a", // zombie skin
  e: "#4a5a3a", // zombie skin shadow
  r: "#9e2d22", // blood / wound
  W: "#e8dcc8", // bone / cloth highlight
  p: "#6b3fa0", // Samedi purple (hex glow core)
  P: "#9a6ab8", // hex glow light
  m: "#b5452a", // mesa red
  M: "#7a2e1a", // mesa shadow
  n: "#c4a265", // sand
  N: "#a68b4b", // sand shadow
  c: "#5a7a4a", // cactus green
  t: "#4ecdc4", // ashfall teal (glow)
};

// --- APPROVED SEED SPRITES (verified via show_widget 2026-06-16) ---
const SPRITES = {
  gunslinger: [
    "................",
    ".....bbbbbb.....",
    "....bKKKKKKb....",
    "...bKKKKKKKKb...",
    "....bbbbbbbb....",
    ".....SSSSSS.....",
    ".....SbSSbS.....",
    ".....SSSSSS.....",
    "......dSSd......",
    "....bLLLLLLb....",
    "...bLlLLLlLb...",
    "...bLlLDDlLb...",
    "..GbLlLDDlLbG..",
    "..GbLLLLLLLbG..",
    "...bLLLLLLLb...",
    "...bLLb.bLLb...",
    "...bDDb.bDDb...",
    "...bDDb.bDDb...",
    "...bbbb.bbbb...",
    "..bbbbb.bbbbb..",
  ],
  hexslinger: [
    "................",
    ".....bbbbbb.....",
    "....bKKKKKKb....",
    "...bKKKKKKKKb...",
    "....bbbbbbbb....",
    ".....SSSSSS.....",
    ".....SbSSbS.....",
    ".....SSSSSS.....",
    "......dSSd......",
    "....bDDDDDDb....",
    "...bDLWWLDb....",
    "..PpbDLLLDbG...",
    "..PpbDDDDDbG...",
    "...bDDDDDDb....",
    "...bDDDDDDb....",
    "...bLLb.bLLb...",
    "...bDDb.bDDb...",
    "...bDDb.bDDb...",
    "...bbbb.bbbb...",
    "..bbbbb.bbbbb..",
  ],
  walkin_dead: [
    "................",
    ".....bbbbb......",
    "....bgggggb....",
    "....bgrgggb....",
    "....bggeggb....",
    ".....bgggb.....",
    "......eee......",
    "...bgggggggb...",
    "..bggeggggbg...",
    "..gbggDDgggbg..",
    "..gbgggggggb...",
    "...bgggggggb...",
    "...bgggggggb...",
    "...bgge.eggb...",
    "...bggb.bggb...",
    "...bggb.bggb...",
    "...bbb...bbb...",
    "..bbbb...bbbb..",
    "................",
    "................",
  ],
  tinkerer: [
    "................",
    ".....bbbbbb.....",
    "....bKKKKKKb....",
    "...bKKKKKKKKb...",
    "....bBBBBBBb....",
    ".....SSSSSS.....",
    ".....StSStS.....",
    ".....SSSSSS.....",
    "......dSSd......",
    "...BbLLLLLLbB...",
    "...BbLlBBlLbB...",
    "...BbLlLLlLbB...",
    "..GbLlLLLLlbG..",
    "..GbLLLLLLLbG..",
    "...bLLLLLLLb...",
    "...bLLb.bLLb...",
    "...bDDb.bDDb...",
    "...bDDb.bDDb...",
    "...bbbb.bbbb...",
    "..bbbbb.bbbbb..",
  ],
  preacher: [
    "................",
    "....bbbbbbbb....",
    "...bKKKKKKKKb...",
    "...bKKKKKKKKb...",
    "....bbbbbbbb....",
    ".....SSSSSS.....",
    ".....SbSSbS.....",
    ".....SSSSSS.....",
    ".....WWWWWW.....",
    "....bKKKKKKb....",
    "...bKKKWWKKKb...",
    "...bKKKWWKKKb...",
    "..WbKKKKKKKbK..",
    "..WbKKKKKKKbK..",
    "...bKKKKKKKb...",
    "...bKKb.bKKb...",
    "...bKKb.bKKb...",
    "...bKKb.bKKb...",
    "...bbbb.bbbb...",
    "..bbbbb.bbbbb..",
  ],
  lawdog: [
    "................",
    ".....bbbbbb.....",
    "....bKKKKKKb....",
    "...bKKKKKKKKb...",
    "....bbbbbbbb....",
    ".....SSSSSS.....",
    ".....SbSSbS.....",
    ".....SSSSSS.....",
    "......dSSd......",
    "....bDDDDDDb....",
    "...bDDBDDDDb...",
    "...bDDDDDDDb...",
    "..GbDDDDDDDbG..",
    "..GbDDDDDDDbG..",
    "...bDDDDDDDb...",
    "...bDDb.bDDb...",
    "...bDDb.bDDb...",
    "...bDDb.bDDb...",
    "...bbbb.bbbb...",
    "..bbbbb.bbbbb..",
  ],
  drifter: [
    "................",
    "....bbbbbbbb....",
    "...bKKKKKKKKb...",
    "...bKKKKKKKKb...",
    "....bbbbbbbb....",
    ".....SSSSSS.....",
    ".....SbSSbS.....",
    ".....SSSSSS.....",
    "....llllllll...",
    "...lLrLLrLLl...",
    "...lLLLLLLLl...",
    "...lLrLLrLLl...",
    "...llllllll....",
    "....bLLLLb.....",
    "....bDDDDb.....",
    "....bDb.bDb....",
    "....bDb.bDb....",
    "....bbb.bbb....",
    "...bbbb.bbbb...",
    "................",
  ],
  rattlesnake: [
    "................",
    ".....bbbbbb.....",
    "....bKKKKKKb....",
    "...bKKKKKKKKb...",
    "....bbbbbbbb....",
    ".....SSSSSS.....",
    ".....SbSSbS.....",
    ".....rrrrrr.....",
    "......rrrr......",
    "....bLLLLLLb....",
    "...bLrLLrLLb...",
    "...bLLLDDLLb...",
    "..GbLLLDDLLbG..",
    "..GbLLLLLLLbG..",
    "...bLLLLLLLb...",
    "...bLLb.bLLb...",
    "...bDDb.bDDb...",
    "...bDDb.bDDb...",
    "...bbbb.bbbb...",
    "..bbbbb.bbbbb..",
  ],
};

// TODO (overnight): the rest of the roster, each screenshot-verified, same hand-authored bar:
//   archetypes: tinkerer, preacher, lawdog, drifter
//   bestiary T1: rattlesnake_bill(outlaw), forgeworks_sentry, dust_devil, coyote
//   bestiary T2: harrowed_gunfighter, dynamite_bandit, ashfall_golem, dust_witch, thunder_zealot
//   bestiary T3 boss: the_deacon, iron_foreman, hollow_man, coyotes_shadow, the_weaver
//   terrain/iso tiles: sand, mesa(h1/h2), ashfall_vein, crate(cover), cactus(half-cover)
//   overworld: parchment node icons, town/shrine/forge markers

// Generic renderer: paint a sprite's pixels at (ox,oy), each pixel `sc` px. No smoothing → crisp.
function drawSprite(ctx, rows, ox, oy, sc, opts) {
  opts = opts || {};
  for (let r = 0; r < rows.length; r++) {
    const row = rows[r];
    for (let c = 0; c < row.length; c++) {
      let col = SPRITE_PAL[row[c]];
      if (!col) continue;
      if (opts.flash) col = "#ffffff";
      ctx.fillStyle = col;
      ctx.fillRect((ox + c * sc) | 0, (oy + r * sc) | 0, sc, sc);
    }
  }
}

// Map a battle unit to its sprite key. Extend as the roster grows.
function spriteFor(unit) {
  if (!unit) return SPRITES.gunslinger;
  const raw = (unit.archetype || unit.role || unit.name || "")
    .toString()
    .toLowerCase();
  const norm = raw.replace(/[^a-z0-9]/g, ""); // strip spaces/apostrophes/underscores
  for (const k in SPRITES) {
    if (k.replace(/[^a-z0-9]/g, "") === norm) return SPRITES[k];
  }
  if (/dead|risen|harrow|zombie/.test(raw)) return SPRITES.walkin_dead;
  if (/hex|witch|weaver/.test(raw)) return SPRITES.hexslinger;
  return SPRITES.gunslinger;
}

if (typeof window !== "undefined") {
  window.SPRITE_PAL = SPRITE_PAL;
  window.SPRITES = SPRITES;
  window.drawSprite = drawSprite;
  window.spriteFor = spriteFor;
}
