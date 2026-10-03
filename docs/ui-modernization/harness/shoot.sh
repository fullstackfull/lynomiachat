#!/bin/bash
# Builds the harness and captures a gallery (screenshots + control inventory).
# usage: shoot.sh <out_dir>        e.g. shoot.sh docs/ui-modernization/baseline
set -e
R=$(cd "$(dirname "$0")/../../.." && pwd)
OUT=${1:-$R/docs/ui-modernization/baseline}
cd "$R"
npx vite build --config docs/ui-modernization/harness/vite.config.mjs
HARNESS_SURFACES=$(node -e "
  const fs=require('fs');
  const src=fs.readFileSync('docs/ui-modernization/harness/surfaces.js','utf8');
  const slugs=[...src.matchAll(/^  '?([a-z0-9-]+)'?: \{\$/gm)].map(m=>m[1]);
  const route=s=>{const m=src.match(new RegExp(\"'?\"+s+\"'?: \\\\{[\\\\s\\\\S]*?\\\\n  \\\\},\"));return m?(m[0].match(/route: '([^']+)'/)||[])[1]:undefined};
  const state=s=>{const m=src.match(new RegExp(\"'?\"+s+\"'?: \\\\{[\\\\s\\\\S]*?\\\\n  \\\\},\"));return m?(m[0].match(/state: '([^']+)'/)||[])[1]:undefined};
  console.log(JSON.stringify(slugs.map(s=>({slug:s,route:route(s),state:state(s)}))));
")
export HARNESS_SURFACES
CHROMIUM_PATH=${CHROMIUM_PATH:-/opt/pw-browsers/chromium-1194/chrome-linux/chrome} \
  PLAYWRIGHT_MODULE=${PLAYWRIGHT_MODULE:-/opt/node-tools/node_modules/playwright} \
  node docs/ui-modernization/harness/shoot.mjs "$OUT" | tee "$OUT/capture.log"
