# Dustfall — Desktop Packaging (Steam / Epic / GoG)

Dustfall is a self-contained web-tech game (HTML/Canvas/JS, no runtime server or network).
This `electron/` wrapper turns it into a native desktop app. Web tech is the **engine**;
the shipped artifact is a desktop executable.

## Run

```bash
# dev (browser, hot iterate) — no install needed
npm run dev            # npx serve src -l 5174  ->  http://localhost:5174/game.html

# run the actual desktop app
npm install            # pulls electron + electron-builder (~once)
npm start              # launches Dustfall in an Electron window (loads src/game.html locally)
```

## Build installers

```bash
npm install
npm run dist           # all targets for the current OS
npm run dist:win       # Windows  -> dist-electron/Dustfall-Setup-<ver>.exe (NSIS)
npm run dist:mac       # macOS    -> dist-electron/*.dmg
npm run dist:linux     # Linux    -> dist-electron/*.AppImage
```

Output lands in `dist-electron/`. The build is configured in `package.json` -> `build`.

## What's already wired

- **Offline & self-contained.** `electron/main.js` `loadFile`s `src/game.html` from disk — zero network, zero server. Works packaged.
- **Saves persist properly on desktop.** `electron/preload.js` exposes `window.dfNative`; the engine's storage interface (`src/engine.js`) auto-routes saves to the OS userData dir on desktop and falls back to `localStorage` in the browser. Same code, both targets.
- **Fixed-resolution scaling + gamepad-ready input abstraction** are already in the engine.

## Next steps — TIM's, not automated (require accounts / money / signing)

These were deliberately left out of the autonomous build:

1. **Storefront accounts + app IDs:** Steam Direct ($100 recoupable fee per app + account), Epic Games Store, GoG. Create the app, get the App ID.
2. **Steamworks SDK** (achievements, cloud saves, overlay): add `steamworks.js` (or `greenworks`), drop in your `steam_appid.txt`, wire calls. The save layer is already abstracted to make cloud-save adoption easy.
3. **Code signing** so installers don't trip SmartScreen (Windows) / Gatekeeper (macOS): an EV/OV cert (Win) and an Apple Developer cert + notarization (Mac).
4. **(polish) Bundle the Google Fonts locally** (`src/game.html` currently `@import`s them) for pixel-perfect offline typography — currently degrades gracefully to system serif offline.
