// Dustfall — Electron preload. Exposes window.dfNative so the engine's storage
// interface (engine.js) routes saves to the OS userData dir on desktop, and
// transparently falls back to localStorage in the browser. contextIsolation-safe.
const { contextBridge } = require("electron");
const fs = require("fs");
const path = require("path");
const os = require("os");

const base =
  process.env.APPDATA ||
  (process.platform === "darwin"
    ? path.join(os.homedir(), "Library", "Application Support")
    : path.join(os.homedir(), ".local", "share"));
const dir = path.join(base, "Dustfall");
try {
  fs.mkdirSync(dir, { recursive: true });
} catch (e) {}

function file(key) {
  return path.join(dir, String(key).replace(/[^a-z0-9_-]/gi, "_") + ".json");
}

contextBridge.exposeInMainWorld("dfNative", {
  save(key, json) {
    try {
      fs.writeFileSync(file(key), json, "utf8");
    } catch (e) {}
  },
  load(key) {
    try {
      return fs.existsSync(file(key))
        ? fs.readFileSync(file(key), "utf8")
        : null;
    } catch (e) {
      return null;
    }
  },
  wipe(key) {
    try {
      if (fs.existsSync(file(key))) fs.unlinkSync(file(key));
    } catch (e) {}
  },
  platform: process.platform,
});
