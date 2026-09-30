#!/bin/bash
# After the rehearsal (database = the direct path of step 8, on the new image):
# 9. Commerce switches (corrected check), 10. UI smoke, 11. code-only rollback over live Commerce data.
S=$SCRATCH; P=$S/p6/rehearsal
NEW=lynomia/staging:final-f842e12e; OLD=lynomia/staging:4.18-e1cd4c53
KEYS_ENV="--env-file $P/staging.env --env-file $P/encryption.env"
NEW_ENV="$KEYS_ENV --env-file $P/woo.env"
export PGPASSWORD=postgres
echo "== 9. Commerce switches on the new image"
docker run --rm --network host $NEW_ENV -v $P/harness:/harness $NEW bash -lc "bundle exec rails runner /harness/check_commerce_switches.rb p6_final" > $P/commerce_switches.log 2>&1
grep -E '^(PASS|FAIL)' $P/commerce_switches.log | grep -c PASS | sed 's/^/pass=/'; tail -1 $P/commerce_switches.log
echo "== 10. UI smoke on the new image"
$P/ui_rerun.sh
echo "== 11. rollback B over live Commerce data: previous image on this database"
echo "commerce rows: stores=$(psql -h localhost -U postgres -tAc 'select count(*) from commerce_stores' lyn_p6_staging) accounts_with_commerce=$(docker run --rm --network host $KEYS_ENV $NEW bash -lc "bundle exec rails runner 'print Account.all.count { |a| a.feature_enabled?(%q(lynomia_commerce)) }' 2>/dev/null | tail -1")"
docker run --rm --network host $KEYS_ENV -v $P/harness:/harness $OLD bash -lc "bundle exec rails runner /harness/check_existing_whatsapp.rb p6_rollback_codeonly_commerce_data 2>&1 | tail -1" | tee -a $P/harness.log
docker rm -f lyn6-web >/dev/null 2>&1
docker run -d --name lyn6-web --network host $KEYS_ENV $OLD bash -lc "bundle exec rails s -b 127.0.0.1 -p 3100" >/dev/null
until curl -s -o /dev/null -w "%{http_code}" http://localhost:3100/app/login | grep -q 200; do sleep 3; done
echo "previous image over Commerce data: /app/login $(curl -s -o /dev/null -w '%{http_code}' http://localhost:3100/app/login), /api $(curl -s -o /dev/null -w '%{http_code}' http://localhost:3100/api), /webhooks/shopify_commerce $(curl -s -o /dev/null -w '%{http_code}' -X POST http://localhost:3100/webhooks/shopify_commerce)" | tee -a $P/smoke_http.txt
docker logs lyn6-web 2>&1 | grep -c -E "FATAL|Error" | sed 's/^/previous image error lines=/'
docker rm -f lyn6-web >/dev/null
echo "POST DONE"
