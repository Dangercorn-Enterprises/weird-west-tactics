# GameBlocks Usage — Dustfall v1.2 3D battle renderer

Per the GameBlocks skill workflow, this documents which modules/patterns were
used, their reuse status, and how they integrate.

**Context:** Dustfall is a classic-script (non-module) offline game; GameBlocks
ships ES modules pinned to Three r161 CDN imports. Direct module copies would
break the offline/Electron constraint, so patterns were **adapted, not copied**,
against a vendored UMD Three build (`src/vendor/three.min.js`, r147).

| GameBlocks source | Status | Where / how |
|---|---|---|
| `modules/math/WorldBasis.js` | adapted | `src/battle3d.js` ground-plane frame: X=east(q), Z=south(r), Y=up; single source of truth for tile→world transforms (`tx/tz/topY`) |
| `modules/world/environment/BoardEnvironment.js` | adapted | tile board built as per-cell boxes with elevation steps, pickable tops carrying `{q,r}` userData |
| `modules/camera/PositionFollowCameraRig.js` | adapted | fixed orthographic 3/4 rig with azimuth quarter-turn stepping (Q/E), smooth-lerped like the rig's follow easing |
| `modules/behavior/GridPathPlanner.js` | not used | Dustfall's own BFS `reach()` predates it and is battle-logic (mirrored in the balance harness) — swapping it would risk balance drift |
| everything actor-motion / Rapier | not used | turn-based tile game; no continuous physics |

**Integration:** `src/battle3d.js` renders world geometry + units and answers
`project()` / `tileAt()` queries. `src/scene_battle.js` keeps ALL game logic and
its 2D canvas as a transparent overlay (floaters, particles, HP bars, combat
preview). If THREE/WebGL is unavailable, the classic 2D renderer path runs
unchanged.
