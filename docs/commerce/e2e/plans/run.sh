#!/bin/bash
# Runs the stores-on-plans E2E (docs/commerce/35-stores-on-plans.md) against the working tree and its production build
# (made before), on the production configuration: the plain server, Salla/Zid/Shopify switched off.
# usage: run.sh <out_dir> <scratch_dir>   (scratch_dir holds e2e.env, erun.sh and the WooCommerce test stores' Read keys)
OUT=$1; S=$2
R=$(cd "$(dirname "$0")/../../../.." && pwd)
E=$S/commerce/e2e
mkdir -p "$OUT"
K2=($(cat $S/commerce/woo/key2.txt)); K3=($(cat $S/commerce/woo/key3.txt))
KEYS="{\"s2\":{\"ck\":\"${K2[0]}\",\"cs\":\"${K2[1]}\"},\"s3\":{\"ck\":\"${K3[0]}\",\"cs\":\"${K3[1]}\"}}"

$E/erun.sh "bundle exec rails runner docs/commerce/e2e/salla/sim.rb configure off 2>/dev/null | grep '^SIM '; bundle exec rails runner docs/commerce/e2e/zid/sim.rb configure off 2>/dev/null | grep '^SIM '; bundle exec rails runner docs/commerce/e2e/shopify/sim.rb configure off 2>/dev/null | grep '^SIM '"
docker rm -f lyn-plans >/dev/null 2>&1; rm -f $R/tmp/pids/server.pid; : > $R/tmp/e2e_server.log
docker run -d --name lyn-plans --network host --env-file $E/e2e.env -v $R:/app -v lyn_nm:/app/node_modules -w /app lynomia/verify:base \
  bash -lc "bundle exec rails s -b 127.0.0.1 -p 3100 > /app/tmp/e2e_server.log 2>&1" >/dev/null
until curl -s -o /dev/null -w "%{http_code}" http://localhost:3100/app/login | grep -q 200; do sleep 3; done

cd "$R/docs/commerce/e2e/plans"
ERUN=$E/erun.sh CHROMIUM_PATH=${CHROMIUM_PATH:-/opt/pw-browsers/chromium-1194/chrome-linux/chrome} \
  PLAYWRIGHT_MODULE=${PLAYWRIGHT_MODULE:-/opt/node22/lib/node_modules/playwright} node e2e_plans.js "$OUT" "$KEYS" | tee "$OUT/e2e_plans.log"
cp "$R/tmp/e2e_server.log" "$OUT/"
docker rm -f lyn-plans >/dev/null 2>&1
