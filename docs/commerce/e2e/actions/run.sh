#!/bin/bash
# Runs the Phase 9–10 E2E (docs/commerce/33-phase9-10-e2e.md) against the working tree and its production build (made
# before): first the production configuration ("gate": real WooCommerce actions, Salla/Zid/Shopify held back), then the
# same app restarted with COMMERCE_ALLOW_PRE_UAT_PROVIDERS ("sim": simulated Zid/Shopify actions, carts, recovery).
# usage: run.sh <out_dir> <scratch_dir>   (scratch_dir holds e2e.env, erun.sh, the WooCommerce wp.sh and read-only keys)
set -e
OUT=$1; S=$2
R=$(cd "$(dirname "$0")/../../../.." && pwd)
E=$S/commerce/e2e
WP=$S/commerce/woo/wp.sh
mkdir -p "$OUT"

# The disposable test store: its delivery route to Lynomia and the test-only refund gateway (never on a merchant's store).
GATEWAY=$(docker network inspect woo-net --format '{{range .IPAM.Config}}{{.Gateway}}{{end}}')
sed "s/__GATEWAY__/$GATEWAY/" "$R/docs/commerce/e2e/woocommerce/lynomia-e2e-delivery.php" | docker exec -i woo-wp sh -c \
  'mkdir -p /var/www/html/wp-content/mu-plugins && cat > /var/www/html/wp-content/mu-plugins/lynomia-e2e-delivery.php'
docker exec -i woo-wp sh -c 'cat > /var/www/html/wp-content/mu-plugins/lynomia-e2e-gateway.php && chown -R www-data:www-data /var/www/html/wp-content/mu-plugins' \
  < "$R/docs/commerce/e2e/woocommerce/lynomia-e2e-gateway.php"
for id in $($WP wc webhook list --user=1 --format=json --fields=id,name 2>/dev/null | python3 -c 'import json,sys; print(" ".join(str(h["id"]) for h in json.load(sys.stdin) if h["name"] == "Lynomia Commerce"))'); do
  $WP wc webhook delete "$id" --force=true --user=1 >/dev/null 2>&1
done
RW=($($WP eval-file - < "$R/docs/commerce/e2e/woocommerce/apikey_rw.php" 2>/dev/null))
K2=($(cat $S/commerce/woo/key2.txt))
KEYS="{\"rw\":{\"ck\":\"${RW[0]}\",\"cs\":\"${RW[1]}\"},\"s2\":{\"ck\":\"${K2[0]}\",\"cs\":\"${K2[1]}\"}}"

# The sim phase's environment: the E2E one plus the pre-UAT override, for its server, worker and control runner.
SIM_ENV=$S/commerce/e2e/e2e-sim.env
{ cat $E/e2e.env; echo COMMERCE_ALLOW_PRE_UAT_PROVIDERS=true; } > "$SIM_ENV"
cat > $S/commerce/e2e/erun-sim.sh <<RUN
#!/bin/bash
exec docker run --rm --network host --env-file $SIM_ENV -v $R:/app -v lyn_nm:/app/node_modules -w /app lynomia/verify:base bash -lc "\$*"
RUN
chmod +x $S/commerce/e2e/erun-sim.sh

start() { # <env_file>
  docker rm -f lyn9-server lyn9-worker >/dev/null 2>&1 || true
  for role in server worker; do
    docker run -d --name lyn9-$role --network host --env-file "$1" -v $R:/app -v lyn_nm:/app/node_modules -w /app lynomia/verify:base \
      bash -lc "bundle exec rails runner docs/commerce/e2e/actions/$role.rb >> /app/tmp/e2e_$role.log 2>&1" >/dev/null
  done
  until curl -s -o /dev/null -w "%{http_code}" http://localhost:3100/app/login | grep -q 200; do sleep 3; done
  until grep -q "Booted\|Starting processing\|INFO: Booting Sidekiq" "$R/tmp/e2e_worker.log" 2>/dev/null; do sleep 2; done
}

: > "$R/tmp/e2e_server.log"; : > "$R/tmp/e2e_worker.log"; : > "$R/tmp/e2e_ctl.log"
$E/erun.sh "bundle exec rails runner 'User.where(\"email LIKE ?\", \"%@commerce.lynomia.local\").find_each { |u| u.update_columns(tokens: {}); u.user_sessions.destroy_all }; puts :sessions_cleared' 2>/dev/null | tail -1"
cd "$R/docs/commerce/e2e/actions"
export WP SERVER_LOG=$R/tmp/e2e_server.log WORKER_LOG=$R/tmp/e2e_worker.log CTL_LOG=$R/tmp/e2e_ctl.log
export CHROMIUM_PATH=${CHROMIUM_PATH:-/opt/pw-browsers/chromium-1194/chrome-linux/chrome} PLAYWRIGHT_MODULE=${PLAYWRIGHT_MODULE:-/opt/node22/lib/node_modules/playwright}
export E2E_SHOPIFY_CLIENT_SECRET=$(grep '^E2E_SHOPIFY_CLIENT_SECRET=' $E/e2e.env | cut -d= -f2)
set +e
start $E/e2e.env
ERUN=$E/erun.sh node e2e_actions.js gate "$OUT" "$KEYS" | tee "$OUT/e2e_actions_gate.log"
start "$SIM_ENV"
ERUN=$S/commerce/e2e/erun-sim.sh node e2e_actions.js sim "$OUT" "$KEYS" | tee "$OUT/e2e_actions_sim.log"
cp "$R/tmp/e2e_server.log" "$R/tmp/e2e_worker.log" "$R/tmp/e2e_ctl.log" "$OUT/"
docker rm -f lyn9-server lyn9-worker >/dev/null 2>&1
rm -f "$SIM_ENV" $S/commerce/e2e/erun-sim.sh

# The test store back to its seeded state for the other E2Es: this run's orders (and their refunds), Lynomia's webhooks,
# the test gateway and its mail capture.
for id in $(python3 -c 'import json,sys; print(" ".join(json.load(open(sys.argv[1])).values()))' "$OUT/woo_orders.json" 2>/dev/null); do
  $WP wc shop_order delete "$id" --force=true --user=1 >/dev/null 2>&1
done
for id in $($WP wc webhook list --user=1 --format=json --fields=id,name 2>/dev/null | python3 -c 'import json,sys; print(" ".join(str(h["id"]) for h in json.load(sys.stdin) if h["name"] == "Lynomia Commerce"))'); do
  $WP wc webhook delete "$id" --force=true --user=1 >/dev/null 2>&1
done
docker exec woo-wp rm -f /var/www/html/wp-content/mu-plugins/lynomia-e2e-gateway.php
$WP option delete lynomia_e2e_gateway_calls lynomia_e2e_mails >/dev/null 2>&1
python3 -c "import json,sys; r=[x for f in sys.argv[1:] for x in json.load(open(f))]; print(f'TOTAL {sum(x[\"ok\"] for x in r)}/{len(r)} passed')" "$OUT/results-gate.json" "$OUT/results-sim.json"
