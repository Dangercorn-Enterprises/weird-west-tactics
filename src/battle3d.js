// =============================================
// DUSTFALL — 3D BATTLE RENDERER (v1.2 graphics pass)
// FFT-style presentation: orthographic 3/4 camera over real 3D tile boxes with
// elevation, directional light + soft shadows, and billboard pixel sprites
// (crisp NearestFilter — the Ivalice look). The battle LOGIC in scene_battle.js
// is untouched: this module only draws world geometry + units and answers
// picking/projection queries. Text, floaters, particles, HP bars and the
// combat preview stay on the transparent 2D overlay canvas above this one.
// Patterns adapted from the GameBlocks skill (BoardEnvironment tile board,
// WorldBasis ground-plane frame, PoseFollow-style rig) — see gameblocks_usage.md.
// Requires vendor/three.min.js (r147 UMD, offline). Falls back cleanly: if
// WebGL or THREE is missing, scene_battle keeps its classic 2D canvas path.
// =============================================
(function () {
  "use strict";
  const DF = (window.DF = window.DF || {});

  const COLS = 10,
    ROWS = 10;
  const TILE = 1; // world units per tile
  const STEP = 0.55; // world height per elevation level
  const BASE = 0.32; // ground slab thickness
  const W = 900,
    H = 620; // logical canvas size (matches the 2D overlay)

  let renderer = null,
    scene,
    camera,
    raycaster,
    ready = false;
  let boardGroup = null, // tiles + decos (rebuilt per battle)
    unitGroup = null,
    fxGroup = null; // highlights (reachable/hover/selection)
  let tileMeshes = []; // pickable tops, userData {q,r}
  let gridRef = null,
    floors = ["#3a2c18", "#4a3820", "#5a4428"];
  let azimuth = Math.PI / 4, // 45° — FFT home angle
    targetAzimuth = Math.PI / 4;
  const ELEV = 0.62; // ~35.5° camera elevation (radians)
  let camShake = 0;
  let animated = []; // {sprite, kind, phase} embers/wisps
  const unitSprites = new Map(); // unit.id -> {sprite, shadow, ring, key}
  let texCache = new Map(); // sprite textures + deco textures

  function hasWebGL() {
    try {
      const c = document.createElement("canvas");
      return !!(c.getContext("webgl") || c.getContext("experimental-webgl"));
    } catch (e) {
      return false;
    }
  }

  // ---- world <-> tile frame (WorldBasis-style: X=east(q), Z=south(r), Y=up) --
  const tx = (q) => (q - (COLS - 1) / 2) * TILE;
  const tz = (r) => (r - (ROWS - 1) / 2) * TILE;
  const topY = (h) => BASE + (h || 0) * STEP;

  // ---- init -----------------------------------------------------------------
  function init(wrap, overlayCanvas) {
    if (ready) return true;
    if (typeof THREE === "undefined" || !hasWebGL()) return false;
    // Software rasterizers (SwiftShader/llvmpipe) crawl under AA + soft
    // shadows — detect and degrade so the game stays playable everywhere.
    let soft = false;
    try {
      const probe = document.createElement("canvas").getContext("webgl");
      const dbg = probe.getExtension("WEBGL_debug_renderer_info");
      const name = dbg ? probe.getParameter(dbg.UNMASKED_RENDERER_WEBGL) : "";
      soft = /swiftshader|llvmpipe|software|basic render/i.test(name || "");
    } catch (e) {}
    renderer = new THREE.WebGLRenderer({
      antialias: !soft,
      alpha: true,
      preserveDrawingBuffer: true, // screenshots/captures read the buffer
    });
    renderer.setSize(soft ? W / 2 : W, soft ? H / 2 : H, false);
    renderer.shadowMap.enabled = !soft;
    renderer.shadowMap.type = THREE.PCFSoftShadowMap;
    DF.battle3d.soft = soft;
    const gl = renderer.domElement;
    gl.style.position = "absolute";
    gl.style.left = "0";
    gl.style.top = "0";
    gl.style.borderRadius = "4px";
    gl.style.pointerEvents = "none"; // the 2D overlay keeps all mouse events
    wrap.insertBefore(gl, overlayCanvas);
    // keep the WebGL canvas CSS-locked to the letterboxed overlay
    const match = () => {
      gl.style.width = overlayCanvas.style.width;
      gl.style.height = overlayCanvas.style.height;
    };
    match();
    window.addEventListener("resize", () => setTimeout(match, 0));
    new MutationObserver(match).observe(overlayCanvas, {
      attributes: true,
      attributeFilter: ["style"],
    });

    scene = new THREE.Scene();
    const aspect = W / H;
    const viewH = 10.6; // frustum height in world units (tuned to frame 10x10)
    camera = new THREE.OrthographicCamera(
      (-viewH * aspect) / 2,
      (viewH * aspect) / 2,
      viewH / 2,
      -viewH / 2,
      0.1,
      100,
    );
    placeCamera();

    // desert light: warm key + cool ambient fill
    const hemi = new THREE.HemisphereLight(0xcdbf9f, 0x2a1d0f, 0.75);
    scene.add(hemi);
    const sun = new THREE.DirectionalLight(0xffe0b0, 1.05);
    sun.position.set(6, 11, 4);
    sun.castShadow = !soft;
    sun.shadow.mapSize.set(soft ? 512 : 2048, soft ? 512 : 2048);
    sun.shadow.camera.left = -9;
    sun.shadow.camera.right = 9;
    sun.shadow.camera.top = 9;
    sun.shadow.camera.bottom = -9;
    sun.shadow.camera.far = 40;
    sun.shadow.bias = -0.0008;
    scene.add(sun);

    raycaster = new THREE.Raycaster();
    unitGroup = new THREE.Group();
    fxGroup = new THREE.Group();
    scene.add(unitGroup);
    scene.add(fxGroup);
    ready = true;
    return true;
  }

  function placeCamera() {
    const dist = 26;
    camera.position.set(
      Math.sin(azimuth) * Math.cos(ELEV) * dist,
      Math.sin(ELEV) * dist,
      Math.cos(azimuth) * Math.cos(ELEV) * dist,
    );
    camera.lookAt(0, 0.8, 0);
    camera.updateProjectionMatrix();
    camera.updateMatrixWorld();
  }

  // ---- pixel-art toolkit (v1.2.1): scale2x + ink outline + top-light shade ---
  // scale2x doubles resolution while smoothing stair-steps; run twice for 4x.
  function scale2x(img) {
    const { data, w, h } = img;
    const out = new Uint32Array(w * h * 4);
    const W = w * 2;
    const px = (x, y) =>
      x < 0 || y < 0 || x >= w || y >= h ? 0 : data[y * w + x];
    for (let y = 0; y < h; y++)
      for (let x = 0; x < w; x++) {
        const P = px(x, y),
          A = px(x, y - 1),
          B = px(x + 1, y),
          C = px(x - 1, y),
          D = px(x, y + 1);
        let e0 = P,
          e1 = P,
          e2 = P,
          e3 = P;
        if (C === A && C !== D && A !== B) e0 = A;
        if (A === B && A !== C && B !== D) e1 = B;
        if (D === C && D !== B && C !== A) e2 = C;
        if (B === D && B !== A && D !== C) e3 = D;
        const o = y * 2 * W + x * 2;
        out[o] = e0;
        out[o + 1] = e1;
        out[o + W] = e2;
        out[o + W + 1] = e3;
      }
    return { data: out, w: W, h: h * 2 };
  }
  // 1px dark ink outline around every opaque region (the FFT silhouette pop)
  function inkOutline(img) {
    const { data, w, h } = img;
    const INK = 0xff050c12; // ABGR: near-black warm ink
    const out = data.slice();
    for (let y = 0; y < h; y++)
      for (let x = 0; x < w; x++) {
        const i = y * w + x;
        if (data[i] !== 0) continue;
        const n =
          (x > 0 && data[i - 1]) ||
          (x < w - 1 && data[i + 1]) ||
          (y > 0 && data[i - w]) ||
          (y < h - 1 && data[i + w]);
        if (n) out[i] = INK;
      }
    img.data = out;
  }
  // vertical light: heads catch the sun, boots sit in dust
  function topLight(img) {
    const { data, w, h } = img;
    for (let y = 0; y < h; y++) {
      const f = 1.08 - (y / h) * 0.28;
      for (let x = 0; x < w; x++) {
        const i = y * w + x;
        const c = data[i];
        if (c === 0) continue;
        const a = c & 0xff000000;
        let r = (c >> 16) & 0xff,
          g = (c >> 8) & 0xff,
          b = c & 0xff;
        b = Math.min(255, (b * f) | 0);
        g = Math.min(255, (g * f) | 0);
        r = Math.min(255, (r * f) | 0);
        data[i] = a | (r << 16) | (g << 8) | b;
      }
    }
  }
  // integer nearest upscale — chunky pixels, no smoothing (FFT keeps its jaggies)
  function nearestScale(img, k) {
    const { data, w, h } = img;
    const out = new Uint32Array(w * k * h * k);
    for (let y = 0; y < h * k; y++)
      for (let x = 0; x < w * k; x++)
        out[y * w * k + x] = data[((y / k) | 0) * w + ((x / k) | 0)];
    return { data: out, w: w * k, h: h * k };
  }
  // horizontal light: the sun sits up-left of the camera home angle
  function sideLight(img) {
    const { data, w, h } = img;
    for (let y = 0; y < h; y++)
      for (let x = 0; x < w; x++) {
        const i = y * w + x;
        const c = data[i];
        if (c === 0) continue;
        const f = 1.05 - (x / w) * 0.12;
        const a = c & 0xff000000;
        let r = (c >> 16) & 0xff,
          g = (c >> 8) & 0xff,
          b = c & 0xff;
        b = Math.min(255, (b * f) | 0);
        g = Math.min(255, (g * f) | 0);
        r = Math.min(255, (r * f) | 0);
        data[i] = a | (r << 16) | (g << 8) | b;
      }
  }
  function imgToCanvas(img) {
    const c = document.createElement("canvas");
    c.width = img.w;
    c.height = img.h;
    const x = c.getContext("2d");
    const id = x.createImageData(img.w, img.h);
    new Uint32Array(id.data.buffer).set(img.data);
    x.putImageData(id, 0, 0);
    return c;
  }
  const hexToU32 = (hex) => {
    const n = parseInt(hex.slice(1), 16);
    // canvas ImageData is little-endian RGBA -> u32 ABGR
    return (
      ((0xff << 24) |
        ((n & 0xff) << 16) |
        (n & 0xff00) |
        ((n >> 16) & 0xff)) >>>
      0
    );
  };

  // ---- terrain textures (v1.2.1): generated per-biome tops + strata sides ----
  function tileTopTexture(biomeId, base, level, variant) {
    const key = "top:" + biomeId + ":" + level + ":" + variant;
    if (texCache.has(key)) return texCache.get(key);
    const size = 48;
    const c = document.createElement("canvas");
    c.width = c.height = size;
    const x = c.getContext("2d");
    x.fillStyle = base;
    x.fillRect(0, 0, size, size);
    // deterministic per-variant noise
    let seed = variant * 9973 + level * 131 + biomeId.length * 17 + 7;
    const rnd = () => (seed = (seed * 16807) % 2147483647) / 2147483647;
    for (let i = 0; i < 110; i++) {
      x.fillStyle = rnd() < 0.55 ? "rgba(0,0,0,.10)" : "rgba(255,255,255,.06)";
      x.fillRect((rnd() * size) | 0, (rnd() * size) | 0, 1 + ((rnd() * 2) | 0), 1);
    }
    // hairline cracks
    x.strokeStyle = "rgba(0,0,0,.16)";
    x.lineWidth = 1;
    for (let i = 0; i < 2 + (variant % 2); i++) {
      x.beginPath();
      let cx = rnd() * size,
        cy = rnd() * size;
      x.moveTo(cx, cy);
      for (let sgm = 0; sgm < 3; sgm++) {
        cx += rnd() * 14 - 7;
        cy += rnd() * 14 - 7;
        x.lineTo(cx, cy);
      }
      x.stroke();
    }
    // biome accents
    if (biomeId === "mesa") {
      for (let i = 0; i < 5; i++) {
        x.fillStyle = "rgba(0,0,0,.15)";
        x.beginPath();
        x.ellipse(rnd() * size, rnd() * size, 1.5 + rnd() * 1.5, 1 + rnd(), 0, 0, 7);
        x.fill();
      }
      x.strokeStyle = "rgba(150,150,80,.35)";
      for (let i = 0; i < 3; i++) {
        const gx = rnd() * size,
          gy = rnd() * size;
        x.beginPath();
        x.moveTo(gx, gy);
        x.lineTo(gx - 1, gy - 3);
        x.moveTo(gx, gy);
        x.lineTo(gx + 1, gy - 3);
        x.stroke();
      }
    } else if (biomeId === "canyon") {
      for (let i = 0; i < 4; i++) {
        x.fillStyle = i % 2 ? "rgba(120,50,25,.10)" : "rgba(0,0,0,.08)";
        x.fillRect(0, (rnd() * size) | 0, size, 2 + ((rnd() * 3) | 0));
      }
    } else if (biomeId === "town") {
      // worn cobbles / boardwalk seams
      x.strokeStyle = "rgba(0,0,0,.15)";
      for (let gy = 8 + ((rnd() * 4) | 0); gy < size; gy += 12) {
        x.beginPath();
        x.moveTo(0, gy);
        x.lineTo(size, gy);
        x.stroke();
      }
      for (let i = 0; i < 4; i++) {
        const bx = (rnd() * size) | 0,
          by = 8 + ((rnd() * 3) | 0) * 12;
        x.beginPath();
        x.moveTo(bx, by - 12);
        x.lineTo(bx, by);
        x.stroke();
      }
    } else if (biomeId === "boneyard") {
      for (let i = 0; i < 26; i++) {
        x.fillStyle = "rgba(216,210,192,.14)";
        x.fillRect((rnd() * size) | 0, (rnd() * size) | 0, 1, 1);
      }
      x.fillStyle = "rgba(216,210,192,.30)";
      x.fillRect((rnd() * size) | 0, (rnd() * size) | 0, 4, 1);
    } else if (biomeId === "foundry") {
      // riveted plate seams
      x.strokeStyle = "rgba(0,0,0,.22)";
      const sy = 12 + ((rnd() * 8) | 0),
        sx2 = 12 + ((rnd() * 8) | 0);
      x.beginPath();
      x.moveTo(0, sy);
      x.lineTo(size, sy);
      x.moveTo(sx2, 0);
      x.lineTo(sx2, size);
      x.stroke();
      x.fillStyle = "rgba(180,140,60,.45)";
      [4, 20, 36].forEach((d) => {
        x.fillRect(sx2 - 1, d, 2, 2);
        x.fillRect(d, sy - 1, 2, 2);
      });
    } else if (biomeId === "hollow") {
      x.strokeStyle = "rgba(42,250,199,.12)";
      for (let i = 0; i < 3; i++) {
        x.beginPath();
        let vx = rnd() * size,
          vy = rnd() * size;
        x.moveTo(vx, vy);
        for (let sgm = 0; sgm < 4; sgm++) {
          vx += rnd() * 10 - 5;
          vy += rnd() * 10 - 5;
          x.lineTo(vx, vy);
        }
        x.stroke();
      }
    }
    // FFT tile bevel: sunlit top-left lip, shaded bottom-right
    x.fillStyle = "rgba(255,235,200,.18)";
    x.fillRect(0, 0, size, 2);
    x.fillRect(0, 0, 2, size);
    x.fillStyle = "rgba(0,0,0,.30)";
    x.fillRect(0, size - 3, size, 3);
    x.fillRect(size - 3, 0, 3, size);
    const tex = new THREE.CanvasTexture(c);
    tex.magFilter = THREE.NearestFilter;
    tex.minFilter = THREE.NearestFilter;
    texCache.set(key, tex);
    return tex;
  }
  function tileSideTexture(biomeId, base, variant) {
    const key = "side:" + biomeId + ":" + variant;
    if (texCache.has(key)) return texCache.get(key);
    const size = 48;
    const c = document.createElement("canvas");
    c.width = c.height = size;
    const x = c.getContext("2d");
    x.fillStyle = base;
    x.fillRect(0, 0, size, size);
    x.fillStyle = "rgba(0,0,0,.42)"; // sides sit in their own shade
    x.fillRect(0, 0, size, size);
    let seed = variant * 7919 + biomeId.length * 23 + 3;
    const rnd = () => (seed = (seed * 16807) % 2147483647) / 2147483647;
    // sediment strata
    for (let i = 0; i < 5; i++) {
      x.fillStyle = i % 2 ? "rgba(0,0,0,.16)" : "rgba(255,220,170,.05)";
      x.fillRect(0, (rnd() * size) | 0, size, 2 + ((rnd() * 3) | 0));
    }
    for (let i = 0; i < 40; i++) {
      x.fillStyle = rnd() < 0.5 ? "rgba(0,0,0,.12)" : "rgba(255,255,255,.04)";
      x.fillRect((rnd() * size) | 0, (rnd() * size) | 0, 2, 1);
    }
    // dark lip under the tile top
    x.fillStyle = "rgba(0,0,0,.35)";
    x.fillRect(0, 0, size, 3);
    const tex = new THREE.CanvasTexture(c);
    tex.magFilter = THREE.NearestFilter;
    tex.minFilter = THREE.NearestFilter;
    texCache.set(key, tex);
    return tex;
  }

  // ---- board ------------------------------------------------------------------
  const shade = (hex, f) => new THREE.Color(hex).multiplyScalar(f);
  function buildBoard(grid, biome) {
    gridRef = grid;
    floors = (biome && biome.floors) || floors;
    if (boardGroup) {
      scene.remove(boardGroup);
      boardGroup.traverse((o) => {
        if (o.geometry) o.geometry.dispose();
      });
    }
    boardGroup = new THREE.Group();
    tileMeshes = [];
    animated = [];
    for (let r = 0; r < ROWS; r++)
      for (let q = 0; q < COLS; q++) {
        const cell = grid[r][q];
        const h = topY(cell.h);
        const geo = new THREE.BoxGeometry(TILE * 0.98, h, TILE * 0.98);
        const variant = (q * 7 + r * 13) % 3; // 3 texture variants per biome
        const vary = 0.96 + ((q * 5 + r * 11) % 4) * 0.025; // checker life
        const bid = (biome && biome.id) || "mesa";
        const top = new THREE.MeshLambertMaterial({
          map: tileTopTexture(bid, floors[Math.min(2, cell.h)], cell.h, variant),
          color: new THREE.Color(vary, vary, vary),
        });
        const side = new THREE.MeshLambertMaterial({
          map: tileSideTexture(bid, floors[0], variant),
          color: new THREE.Color(vary, vary, vary),
        });
        const mesh = new THREE.Mesh(geo, [side, side, top, side, side, side]);
        mesh.position.set(tx(q), h / 2, tz(r));
        mesh.castShadow = true;
        mesh.receiveShadow = true;
        mesh.userData = { q, r };
        boardGroup.add(mesh);
        tileMeshes.push(mesh);
        if (cell.deco && cell.deco !== "mesa") addDeco(cell, q, r);
      }
    scene.add(boardGroup);
  }

  // ---- decos: tiny generated pixel textures on upright billboards -------------
  function decoTexture(kind) {
    const key = "deco:" + kind;
    if (texCache.has(key)) return texCache.get(key);
    const c = document.createElement("canvas");
    c.width = 48;
    c.height = 56;
    const x = c.getContext("2d");
    const px = (col, ...rects) => {
      x.fillStyle = col;
      rects.forEach(([a, b, w, h]) => x.fillRect(a, b, w, h));
    };
    if (kind === "crate")
      px("#6b4a26", [8, 20, 32, 32]) ||
        px("#3a2814", [8, 20, 32, 4], [8, 34, 32, 3], [22, 20, 4, 32]);
    else if (kind === "barrel")
      px("#7a5a30", [12, 16, 24, 38]) ||
        px("#3a2814", [12, 26, 24, 3], [12, 40, 24, 3]) ||
        px("#936037", [12, 16, 4, 38]);
    else if (kind === "cactus")
      px("#5a7a4a", [20, 8, 8, 44], [8, 18, 12, 7], [28, 12, 12, 7]) ||
        px("#4a6a3a", [8, 18, 5, 14], [35, 12, 5, 12]);
    else if (kind === "rock")
      px("#6e523a", [6, 30, 36, 22]) ||
        px("#54402c", [14, 22, 24, 12]) ||
        px("#7d6045", [10, 26, 10, 8]);
    else if (kind === "grave")
      px("#8a857a", [14, 14, 20, 40]) ||
        px("#6f6a5e", [14, 14, 20, 4], [18, 26, 12, 3]) ||
        px("#5c584e", [10, 50, 28, 4]);
    else if (kind === "bone")
      px("#d8d2c0", [10, 40, 28, 5], [8, 34, 6, 6], [34, 34, 6, 6]) ||
        px("#b8b2a0", [16, 28, 4, 14], [26, 26, 4, 16]);
    else if (kind === "pipe")
      px("#8899aa", [18, 8, 12, 46]) ||
        px("#b08830", [14, 8, 20, 5]) ||
        px("#5a6a7a", [18, 8, 4, 46]);
    else if (kind === "ember")
      px("#d4763a", [18, 38, 12, 10]) ||
        px("#e8a04f", [21, 33, 6, 6]) ||
        px("#f4d27a", [23, 28, 3, 4]);
    else if (kind === "spire")
      px("#3d4a50", [20, 6, 8, 48], [16, 22, 16, 6]) ||
        px("#2c363c", [20, 6, 3, 48]);
    else if (kind === "wisp")
      px("rgba(42,250,199,.85)", [20, 22, 8, 8]) ||
        px("rgba(42,250,199,.4)", [16, 18, 16, 16]);
    const tex = new THREE.CanvasTexture(c);
    tex.magFilter = THREE.NearestFilter;
    tex.minFilter = THREE.NearestFilter;
    texCache.set(key, tex);
    return tex;
  }
  function addDeco(cell, q, r) {
    const tex = decoTexture(cell.deco);
    const mat = new THREE.SpriteMaterial({ map: tex, transparent: true });
    const s = new THREE.Sprite(mat);
    const sc = cell.deco === "spire" ? 1.25 : 0.85;
    s.scale.set(sc * 0.86, sc, 1);
    s.position.set(tx(q), topY(cell.h) + sc / 2 - 0.04, tz(r));
    boardGroup.add(s);
    if (cell.deco === "ember" || cell.deco === "wisp")
      animated.push({ sprite: s, kind: cell.deco, phase: q * 3 + r });
  }

  // ---- unit sprites ------------------------------------------------------------
  function unitTexture(u, flash) {
    const rows = typeof spriteFor === "function" ? spriteFor(u) : null;
    const key = "unit:" + (u.archetype || u.name) + (flash ? ":f" : "");
    if (texCache.has(key)) return texCache.get(key);
    let canvas;
    if (rows && typeof SPRITE_PAL !== "undefined") {
      // rasterize the 16x20 pixel data, then polish: scale2x x2 (64x80,
      // smoothed stair-steps) + ink outline + top-light shading — the same
      // character designs with an Ivalice-grade read.
      const w = rows[0].length,
        h = rows.length;
      let img = { data: new Uint32Array(w * h), w, h };
      for (let y = 0; y < h; y++)
        for (let x = 0; x < w; x++) {
          const col = SPRITE_PAL[rows[y][x]];
          if (col) img.data[y * w + x] = flash ? 0xffffffff : hexToU32(col);
        }
      img = scale2x(img); // one pass: de-stairs without going blobby
      if (!flash) {
        topLight(img);
        sideLight(img);
      }
      inkOutline(img); // 1px at 32x40 -> bold 2px after the chunky upscale
      img = nearestScale(img, 2); // 64x80, hard pixel edges preserved
      canvas = imgToCanvas(img);
    } else {
      canvas = document.createElement("canvas");
      canvas.width = 64;
      canvas.height = 80;
      const x = canvas.getContext("2d");
      x.fillStyle = flash ? "#fff" : u.color || "#d4c5a9";
      x.fillRect(16, 16, 32, 56);
    }
    const tex = new THREE.CanvasTexture(canvas);
    tex.magFilter = THREE.NearestFilter;
    tex.minFilter = THREE.NearestFilter;
    texCache.set(key, tex);
    return tex;
  }
  function blobTexture() {
    if (texCache.has("blob")) return texCache.get("blob");
    const c = document.createElement("canvas");
    c.width = c.height = 64;
    const x = c.getContext("2d");
    const g = x.createRadialGradient(32, 32, 4, 32, 32, 30);
    g.addColorStop(0, "rgba(0,0,0,.5)");
    g.addColorStop(1, "rgba(0,0,0,0)");
    x.fillStyle = g;
    x.fillRect(0, 0, 64, 64);
    const tex = new THREE.CanvasTexture(c);
    texCache.set("blob", tex);
    return tex;
  }

  function syncUnits(units, sel) {
    const seen = new Set();
    const t = Date.now();
    units.forEach((u) => {
      seen.add(u.id);
      let rec = unitSprites.get(u.id);
      if (!rec) {
        const mat = new THREE.SpriteMaterial({ transparent: true });
        const sprite = new THREE.Sprite(mat);
        sprite.scale.set(1.08, 1.35, 1); // FFT units loom a little over their tile
        const shadow = new THREE.Sprite(
          new THREE.SpriteMaterial({
            map: blobTexture(),
            transparent: true,
            depthWrite: false,
          }),
        );
        shadow.scale.set(0.8, 0.42, 1);
        const ring = new THREE.Mesh(
          new THREE.RingGeometry(0.34, 0.44, 28),
          new THREE.MeshBasicMaterial({
            color: 0xd4a843,
            transparent: true,
            opacity: 0.9,
            side: THREE.DoubleSide,
          }),
        );
        ring.rotation.x = -Math.PI / 2;
        unitGroup.add(sprite);
        unitGroup.add(shadow);
        unitGroup.add(ring);
        rec = { sprite, shadow, ring, key: null };
        unitSprites.set(u.id, rec);
      }
      const flash = u.flash > 0;
      const key = (u.archetype || u.name) + (flash ? ":f" : "");
      if (rec.key !== key) {
        rec.sprite.material.map = unitTexture(u, flash);
        rec.sprite.material.needsUpdate = true;
        rec.key = key;
      }
      const q = u.px !== undefined ? u.px : u.q;
      const r = u.py !== undefined ? u.py : u.r;
      const cell =
        gridRef && gridRef[Math.round(u.r)]
          ? gridRef[Math.round(u.r)][Math.round(u.q)]
          : null;
      const y = topY(cell ? cell.h : 0);
      const bob = Math.sin(t / 400 + u.q) * 0.02;
      rec.sprite.position.set(tx(q), y + 0.62 + bob, tz(r));
      rec.shadow.position.set(tx(q), y + 0.015, tz(r));
      // billboard shadows lie flat: rotate the sprite plane onto the ground
      rec.shadow.material.rotation = 0;
      rec.ring.visible = sel === u && u.alive;
      rec.ring.position.set(tx(q), y + 0.02, tz(r));
      rec.sprite.material.opacity = u.alive ? 1 : 0;
      rec.shadow.material.opacity = u.alive ? 0.8 : 0;
    });
    // drop sprites for units gone from the field
    unitSprites.forEach((rec, id) => {
      if (!seen.has(id)) {
        unitGroup.remove(rec.sprite);
        unitGroup.remove(rec.shadow);
        unitGroup.remove(rec.ring);
        unitSprites.delete(id);
      }
    });
  }

  // ---- move-range / hover highlights -------------------------------------------
  let hlPool = [];
  function syncHighlights(reachable, hover, showReach) {
    hlPool.forEach((m) => (m.visible = false));
    let i = 0;
    const take = (color, opacity) => {
      let m = hlPool[i++];
      if (!m) {
        m = new THREE.Mesh(
          new THREE.PlaneGeometry(TILE * 0.92, TILE * 0.92),
          new THREE.MeshBasicMaterial({
            transparent: true,
            depthWrite: false,
            side: THREE.DoubleSide,
          }),
        );
        m.rotation.x = -Math.PI / 2;
        fxGroup.add(m);
        hlPool.push(m);
      }
      m.material.color.set(color);
      m.material.opacity = opacity;
      m.visible = true;
      return m;
    };
    if (showReach && reachable) {
      Object.keys(reachable).forEach((k) => {
        const [q, r] = k.split(",").map(Number);
        const m = take(0x4ecdc4, 0.3);
        m.position.set(tx(q), topY(gridRef[r][q].h) + 0.012, tz(r));
      });
    }
    if (hover && gridRef && gridRef[hover.r]) {
      const m = take(0xd4a843, 0.3);
      m.position.set(
        tx(hover.q),
        topY(gridRef[hover.r][hover.q].h) + 0.014,
        tz(hover.r),
      );
    }
  }

  // ---- public API -----------------------------------------------------------------
  DF.battle3d = {
    get ready() {
      return ready;
    },
    init,
    setBoard(grid, biome) {
      if (!ready) return;
      buildBoard(grid, biome);
    },
    rotate(dir) {
      targetAzimuth += (Math.PI / 2) * (dir || 1);
    },
    shake(v) {
      camShake = Math.max(camShake, v || 0);
    },
    sync(state) {
      if (!ready) return;
      syncUnits(state.units, state.sel);
      syncHighlights(state.reachable, state.hover, state.showReach);
      // ambient deco life
      const t = Date.now();
      animated.forEach((a) => {
        const p = Math.sin(t / (a.kind === "ember" ? 260 : 340) + a.phase);
        a.sprite.material.opacity = 0.55 + 0.4 * (p * 0.5 + 0.5);
        if (a.kind === "wisp")
          a.sprite.position.y += Math.sin(t / 300 + a.phase) * 0.0015;
      });
    },
    render() {
      if (!ready) return;
      // smooth Q/E quarter-turns
      const d = targetAzimuth - azimuth;
      if (Math.abs(d) > 0.0005) {
        azimuth += d * 0.14;
        placeCamera();
      }
      if (camShake > 0.05) {
        camera.position.x += (Math.random() - 0.5) * camShake * 0.02;
        camera.position.y += (Math.random() - 0.5) * camShake * 0.015;
        camShake *= 0.85;
      }
      renderer.render(scene, camera);
    },
    // world -> overlay-canvas pixels (used by floaters, particles, previews)
    project(q, r, h) {
      const v = new THREE.Vector3(tx(q), topY(h || 0) + 0.5, tz(r));
      v.project(camera);
      return { x: ((v.x + 1) / 2) * W, y: ((1 - v.y) / 2) * H + 16 };
    },
    // overlay pixels -> tile (raycast picking)
    tileAt(mx, my) {
      if (!ready || !tileMeshes.length) return null;
      const ndc = new THREE.Vector2((mx / W) * 2 - 1, 1 - (my / H) * 2);
      raycaster.setFromCamera(ndc, camera);
      const hit = raycaster.intersectObjects(tileMeshes, false)[0];
      return hit
        ? { q: hit.object.userData.q, r: hit.object.userData.r }
        : null;
    },
  };
})();
