#!/bin/bash
# Phase 6: every Commerce E2E against the final staging image. The servers and every runner command run inside
# lynomia/staging:final-f842e12e (production mode, precompiled assets); only the test fixtures (spec/fixtures, not in
# the image) and tmp (logs the drivers read) are mounted. Order and switches as in Phase 5.
S=$SCRATCH
E=$S/commerce/e2e
X=$S/p6/e2e
R=/home/user/lynomiachat
IMG=lynomia/staging:final-f842e12e
CHROME=/opt/pw-browsers/chromium-1194/chrome-linux/chrome
export PLAYWRIGHT_MODULE=/opt/node22/lib/node_modules/playwright
MOUNTS="-v $R/spec/fixtures:/app/spec/fixtures:ro -v $R/tmp:/app/tmp"
cat > $X/erun.sh <<EOF
#!/bin/bash
exec docker run --rm --network host --env-file $E/e2e.env $MOUNTS -w /app $IMG bash -lc "\$*"
EOF
chmod +x $X/erun.sh
cp $R/docs/commerce/e2e/e2e.js $X/e2e.js
clear_sessions() {
  $X/erun.sh "bundle exec rails runner 'User.where(\"email LIKE ?\", \"%@commerce.lynomia.local\").find_each { |u| u.update_columns(tokens: {}); u.user_sessions.destroy_all }; puts :sessions_cleared' 2>/dev/null | tail -1"
}
server() { # <name> <command>
  docker rm -f lyn6-e2e >/dev/null 2>&1; rm -f $R/tmp/pids/server.pid
  : > $R/tmp/e2e_server.log; : > $R/tmp/e2e_sim.log
  docker run -d --name lyn6-e2e --network host --env-file $E/e2e.env $MOUNTS -w /app $IMG bash -lc "$1 > /app/tmp/e2e_server.log 2>&1" >/dev/null
  until curl -s -o /dev/null -w "%{http_code}" http://localhost:3100/app/login | grep -q 200; do sleep 3; done
}
set -a; . $E/e2e.env; set +a
echo "IMAGE $(docker inspect -f '{{.Id}} {{index .Config.Labels "org.opencontainers.image.revision"}}' $IMG)"
echo "migration level: $($X/erun.sh "bundle exec rails db:migrate:status 2>/dev/null" | grep -c '^\s*up') up, $($X/erun.sh "bundle exec rails db:migrate:status 2>/dev/null" | grep -c '^\s*down') down"
docker start woo-db >/dev/null; sleep 5; docker start woo-wp woo-wp2 woo-wp3 >/dev/null; sleep 10

# 1. Shopify (simulated Shopify inside the server)
clear_sessions
server "bundle exec rails runner docs/commerce/e2e/shopify/server.rb"
rm -rf $X/shopify_p6; mkdir -p $X/shopify_p6
(cd $R/docs/commerce/e2e/shopify && ERUN=$X/erun.sh CHROMIUM_PATH=$CHROME node e2e_shopify.js $X/shopify_p6 > $X/shopify_p6/e2e_shopify_run.log 2>&1)
echo "SHOPIFY: $(tail -1 $X/shopify_p6/e2e_shopify_run.log)"
cp $R/tmp/e2e_server.log $X/shopify_p6/e2e_server.log; cp $R/tmp/e2e_sim.log $X/shopify_p6/e2e_sim.log

# 2. Zid, with Shopify Commerce on (simulated Zid inside the server)
clear_sessions
$X/erun.sh "bundle exec rails runner docs/commerce/e2e/shopify/sim.rb configure on 2>/dev/null | grep '^SIM '"
server "bundle exec rails runner docs/commerce/e2e/zid/server.rb"
rm -rf $X/zid_p6; mkdir -p $X/zid_p6
(cd $R/docs/commerce/e2e/zid && ERUN=$X/erun.sh CHROMIUM_PATH=$CHROME node e2e_zid.js $X/zid_p6 > $X/zid_p6/e2e_zid_run.log 2>&1)
echo "ZID: $(tail -1 $X/zid_p6/e2e_zid_run.log)"
cp $R/tmp/e2e_server.log $X/zid_p6/e2e_server.log; cp $R/tmp/e2e_sim.log $X/zid_p6/e2e_sim.log

# 3. WooCommerce (three real WooCommerce 10.9.4 stores), then Salla, on the plain server
clear_sessions
server "bundle exec rails s -b 127.0.0.1 -p 3100"
K1=($(cat $S/commerce/woo/key.txt)); K2=($(cat $S/commerce/woo/key2.txt)); K3=($(cat $S/commerce/woo/key3.txt))
KEYS="{\"s1\":{\"ck\":\"${K1[0]}\",\"cs\":\"${K1[1]}\"},\"s2\":{\"ck\":\"${K2[0]}\",\"cs\":\"${K2[1]}\"},\"s3\":{\"ck\":\"${K3[0]}\",\"cs\":\"${K3[1]}\"}}"
$X/erun.sh "bundle exec rails runner docs/commerce/e2e/salla/sim.rb configure off 2>/dev/null | grep '^SIM '; bundle exec rails runner docs/commerce/e2e/zid/sim.rb configure off 2>/dev/null | grep '^SIM '; bundle exec rails runner docs/commerce/e2e/shopify/sim.rb configure off 2>/dev/null | grep '^SIM '"
rm -rf $X/woo_p6 $X/salla_p6; mkdir -p $X/woo_p6 $X/salla_p6
(cd $X && CHROMIUM_PATH=$CHROME node e2e.js $X/woo_p6 "$KEYS" > $X/woo_p6/e2e_run.log 2>&1)
echo "WOO: $(tail -1 $X/woo_p6/e2e_run.log)"
cp $R/tmp/e2e_server.log $X/woo_p6/e2e_server.log
(cd $R/docs/commerce/e2e/salla && ERUN=$X/erun.sh CHROMIUM_PATH=$CHROME node e2e_salla.js $X/salla_p6 > $X/salla_p6/e2e_salla_run.log 2>&1)
echo "SALLA: $(tail -1 $X/salla_p6/e2e_salla_run.log)"
cp $R/tmp/e2e_server.log $X/salla_p6/e2e_server.log; cp $R/tmp/e2e_sim.log $X/salla_p6/e2e_sim.log
docker rm -f lyn6-e2e >/dev/null
echo "ALL DONE"
