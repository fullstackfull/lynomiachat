#!/bin/bash
# Runs the Automation E2E (docs/automation/08-e2e.md) against the working tree and its production build (made before),
# on the production configuration: the plain server, a Sidekiq worker, Salla/Zid/Shopify switched off, the disposable
# WooCommerce test store A1 read with its Read key. Its order 23 is moved to paid and back with wp-cli (never a
# merchant's store), and is back to pending when the run ends.
# usage: run.sh <out_dir> <scratch_dir>   (scratch_dir holds e2e.env, erun.sh, wp.sh and the test store's Read key)
OUT=$1; S=$2
R=$(cd "$(dirname "$0")/../../.." && pwd)
E=$S/commerce/e2e
mkdir -p "$OUT"
K1=($(cat $S/commerce/woo/key.txt))
KEYS="{\"s1\":{\"ck\":\"${K1[0]}\",\"cs\":\"${K1[1]}\"}}"

$E/erun.sh "bundle exec rails runner docs/commerce/e2e/salla/sim.rb configure off 2>/dev/null | grep '^SIM '; bundle exec rails runner docs/commerce/e2e/zid/sim.rb configure off 2>/dev/null | grep '^SIM '; bundle exec rails runner docs/commerce/e2e/shopify/sim.rb configure off 2>/dev/null | grep '^SIM '"
$E/erun.sh "bundle exec rails runner 'User.where(\"email LIKE ?\", \"%@commerce.lynomia.local\").find_each { |u| u.update_columns(tokens: {}) }' 2>/dev/null"
docker rm -f lyn-auto lyn-auto-worker >/dev/null 2>&1; rm -f $R/tmp/pids/server.pid; : > $R/tmp/e2e_server.log; : > $R/tmp/e2e_worker.log
docker run -d --name lyn-auto --network host --env-file $E/e2e.env -v $R:/app -v lyn_nm:/app/node_modules -w /app lynomia/verify:base \
  bash -lc "bundle exec rails s -b 127.0.0.1 -p 3100 > /app/tmp/e2e_server.log 2>&1" >/dev/null
until curl -s -o /dev/null -w "%{http_code}" http://localhost:3100/app/login | grep -q 200; do sleep 3; done

cd "$R/docs/automation/e2e"
ERUN=$E/erun.sh WP=$S/commerce/woo/wp.sh WORKER="$R/docs/automation/e2e/worker.sh" SCRATCH=$S WORKER_LOG=$R/tmp/e2e_worker.log \
  CHROMIUM_PATH=${CHROMIUM_PATH:-/opt/pw-browsers/chromium-1194/chrome-linux/chrome} \
  PLAYWRIGHT_MODULE=${PLAYWRIGHT_MODULE:-/opt/node22/lib/node_modules/playwright} node e2e_automation.js "$OUT" "$KEYS" | tee "$OUT/e2e_automation.log"
# The test store's order back to its seeded state, whatever the run did.
$S/commerce/woo/wp.sh wc shop_order update 23 --status=pending --user=1 >/dev/null 2>&1
grep -h '\[Lynomia::Automation\]\|Invalid webhook URL' $R/tmp/e2e_worker.log | sed 's/^.*\(\[Lynomia::Automation\]\|Exception: Invalid webhook URL\)/\1/' > "$OUT/automation_log_lines.txt"
cp "$R/tmp/e2e_server.log" "$R/tmp/e2e_worker.log" "$OUT/"
docker rm -f lyn-auto lyn-auto-worker >/dev/null 2>&1
