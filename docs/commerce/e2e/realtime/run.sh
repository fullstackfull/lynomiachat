#!/bin/bash
# Runs the Phase 7–8 realtime E2E (docs/commerce/27-phase7-8-e2e.md) against the working tree: production build (made
# before), the realtime server and Sidekiq worker (simulated Salla, Zid and Shopify), and the real WooCommerce stores.
# usage: run.sh <out_dir> <scratch_dir>   (scratch_dir holds e2e.env, erun.sh, the WooCommerce wp.sh and read-only keys)
set -e
OUT=$1; S=$2
R=$(cd "$(dirname "$0")/../../../.." && pwd)
E=$S/commerce/e2e
WP=$S/commerce/woo/wp.sh
mkdir -p "$OUT"

# The test store's delivery route to Lynomia on the host (see ../woocommerce/lynomia-e2e-delivery.php).
GATEWAY=$(docker network inspect woo-net --format '{{range .IPAM.Config}}{{.Gateway}}{{end}}')
sed "s/__GATEWAY__/$GATEWAY/" "$R/docs/commerce/e2e/woocommerce/lynomia-e2e-delivery.php" | docker exec -i woo-wp sh -c \
  'mkdir -p /var/www/html/wp-content/mu-plugins && cat > /var/www/html/wp-content/mu-plugins/lynomia-e2e-delivery.php && chown -R www-data:www-data /var/www/html/wp-content/mu-plugins'
# Webhooks an interrupted earlier run left in the test store (a completed run deletes its own on disconnect).
for id in $($WP wc webhook list --user=1 --format=json --fields=id,name 2>/dev/null | python3 -c 'import json,sys; print(" ".join(str(h["id"]) for h in json.load(sys.stdin) if h["name"] == "Lynomia Commerce"))'); do
  $WP wc webhook delete "$id" --force=true --user=1 >/dev/null 2>&1
done
RW=($($WP eval-file - < "$R/docs/commerce/e2e/woocommerce/apikey_rw.php" 2>/dev/null))
K2=($(cat $S/commerce/woo/key2.txt))
KEYS="{\"rw\":{\"ck\":\"${RW[0]}\",\"cs\":\"${RW[1]}\"},\"s2\":{\"ck\":\"${K2[0]}\",\"cs\":\"${K2[1]}\"}}"

docker rm -f lyn7-server lyn7-worker >/dev/null 2>&1 || true
: > "$R/tmp/e2e_server.log"; : > "$R/tmp/e2e_worker.log"; : > "$R/tmp/e2e_ctl.log"
$E/erun.sh "bundle exec rails runner 'User.where(\"email LIKE ?\", \"%@commerce.lynomia.local\").find_each { |u| u.update_columns(tokens: {}); u.user_sessions.destroy_all }; puts :sessions_cleared' 2>/dev/null | tail -1"
for role in server worker; do
  docker run -d --name lyn7-$role --network host --env-file $E/e2e.env -v $R:/app -v lyn_nm:/app/node_modules -w /app lynomia/verify:base \
    bash -lc "bundle exec rails runner docs/commerce/e2e/realtime/$role.rb > /app/tmp/e2e_$role.log 2>&1" >/dev/null
done
until curl -s -o /dev/null -w "%{http_code}" http://localhost:3100/app/login | grep -q 200; do sleep 3; done
until grep -q "Booted\|Starting processing\|INFO: Booting Sidekiq" "$R/tmp/e2e_worker.log" 2>/dev/null; do sleep 2; done

cd "$R/docs/commerce/e2e/realtime"
set +e
ERUN=$E/erun.sh WP=$WP SERVER_LOG=$R/tmp/e2e_server.log WORKER_LOG=$R/tmp/e2e_worker.log CTL_LOG=$R/tmp/e2e_ctl.log \
  CHROMIUM_PATH=${CHROMIUM_PATH:-/opt/pw-browsers/chromium-1194/chrome-linux/chrome} \
  PLAYWRIGHT_MODULE=${PLAYWRIGHT_MODULE:-/opt/node22/lib/node_modules/playwright} node e2e_realtime.js "$OUT" "$KEYS" | tee "$OUT/e2e_realtime_run.log"
cp "$R/tmp/e2e_server.log" "$R/tmp/e2e_worker.log" "$R/tmp/e2e_ctl.log" "$OUT/"
docker rm -f lyn7-server lyn7-worker >/dev/null 2>&1
