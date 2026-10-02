#!/bin/bash
# Runs the canvas performance measurement (canvas.js, docs/flow-builder/09-performance.md) against the working tree's
# production build (made before) on the plain production server and the E2E database, like ../e2e/run.sh.
# usage: canvas.sh <out_dir> <scratch_dir>   (scratch_dir holds commerce/e2e/e2e.env and erun.sh)
OUT=$1; S=$2
R=$(cd "$(dirname "$0")/../../.." && pwd)
E=$S/commerce/e2e
mkdir -p "$OUT"
# Earlier E2E logins count against the users' session limit: start with none, as ../e2e/run.sh does.
"$E/erun.sh" "bundle exec rails runner 'User.where(\"email LIKE ?\", \"%@commerce.lynomia.local\").find_each { |u| u.update_columns(tokens: {}) }' 2>/dev/null"
docker rm -f lyn-flow >/dev/null 2>&1; rm -f "$R/tmp/pids/server.pid"; : > "$R/tmp/e2e_server.log"
docker run -d --name lyn-flow --network host --env-file "$E/e2e.env" -v "$R":/app -v lyn_nm:/app/node_modules -w /app lynomia/verify:base \
  bash -lc "bundle exec rails s -b 127.0.0.1 -p 3100 > /app/tmp/e2e_server.log 2>&1" >/dev/null
until curl -s -o /dev/null -w "%{http_code}" http://localhost:3100/app/login | grep -q 200; do sleep 3; done
cd "$R/docs/flow-builder/perf" || exit 1
ERUN=$E/erun.sh CHROMIUM_PATH=${CHROMIUM_PATH:-/opt/pw-browsers/chromium-1194/chrome-linux/chrome} \
  PLAYWRIGHT_MODULE=${PLAYWRIGHT_MODULE:-/opt/node22/lib/node_modules/playwright} node canvas.js "$OUT" | tee "$OUT/canvas.log"
docker rm -f lyn-flow >/dev/null 2>&1
