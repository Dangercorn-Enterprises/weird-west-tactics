#!/usr/bin/env bash
# =============================================================================
# DUSTFALL — Windows desktop build (Godot 4.7 HD-2D port)
# Produces a standalone dist/dustfall-hd2d.exe (PCK embedded, ~115 MB).
# Prereqs (one-time): export templates installed at
#   %APPDATA%/Godot/export_templates/4.7.stable/  (download the 4.7-stable .tpz)
# Verified booting 2026-07-07: launches title.tscn, both autoloads load the
# packed JSON, exit 0 under --quit-after.
# =============================================================================
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-$LOCALAPPDATA/Microsoft/WinGet/Packages/GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe/Godot_v4.7-stable_win64_console.exe}"

mkdir -p "$HERE/dist"
echo "[1/3] importing assets..."
"$GODOT" --headless --path "$HERE/godot" --import >/dev/null 2>&1 || true

echo "[2/3] exporting Windows release..."
"$GODOT" --headless --path "$HERE/godot" \
  --export-release "Windows Desktop" "../dist/dustfall-hd2d.exe"

echo "[3/3] boot smoke test..."
if timeout 40 "$HERE/dist/dustfall-hd2d.exe" --quit-after 200 >/tmp/dustfall_boot.txt 2>&1; then
  if grep -qiE "SCRIPT ERROR|parse error|null instance" /tmp/dustfall_boot.txt; then
    echo "  FAIL — runtime error on boot:"; grep -iE "SCRIPT ERROR|parse|null" /tmp/dustfall_boot.txt | head
    exit 1
  fi
  echo "  OK — build boots clean: $(ls -la "$HERE/dist/dustfall-hd2d.exe" | awk '{print $5}') bytes"
else
  echo "  FAIL — nonzero exit on boot"; exit 1
fi
