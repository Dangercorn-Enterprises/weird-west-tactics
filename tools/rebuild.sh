#!/usr/bin/env bash
# One-command rebuild: re-extract spec from src/haunts.js + re-render catalog.
# Run after any edit to src/haunts.js to keep data/ + docs/ in sync.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
cd "$HERE/.."
node tools/extract_haunt_spec.js
node tools/render_wave_catalog.js
echo
echo "Everything is in sync. Files updated:"
echo "  data/haunt_spec.json       (engine-agnostic source of truth)"
echo "  docs/HAUNT_WAVE_CATALOG.md (human-readable reference)"
