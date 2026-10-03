#!/bin/bash
# Runs the usability journeys (docs/usability/07-e2e.md) in a real Chromium against a built harness of the components
# this phase changed. No Rails, no database, no network.
# usage: run.sh [out_dir]
set -e
R=$(cd "$(dirname "$0")/../../.." && pwd)
OUT=${1:-$R/docs/usability/e2e/results}
cd "$R"
npx vite build --config docs/usability/e2e/harness/vite.config.mjs
mkdir -p "$OUT"
CHROMIUM_PATH=${CHROMIUM_PATH:-/opt/pw-browsers/chromium-1194/chrome-linux/chrome} \
  PLAYWRIGHT_MODULE=${PLAYWRIGHT_MODULE:-/opt/node-tools/node_modules/playwright} \
  node docs/usability/e2e/journeys.mjs "$OUT" | tee "$OUT/journeys.log"
