#!/bin/bash
# Phase 6 deployment and rollback rehearsal on the final image (docs/commerce/23-real-uat-and-production-gate.md §9-10).
# "Production" before the release = the last approved image (4.18-e1cd4c53) on the Phase 4 pre-deploy backup.
S=$SCRATCH
P=$S/p6/rehearsal
NEW=lynomia/staging:final-f842e12e
OLD=lynomia/staging:4.18-e1cd4c53
DB=lyn_p6_staging
export PGPASSWORD=postgres
q() { psql -h localhost -U postgres -tAc "$1" $DB; }
run() { local img=$1 envs=$2; shift 2; docker run --rm --network host $envs -v $P/harness:/harness $img bash -lc "$*"; }
BASE_ENV="--env-file $P/staging.env"
KEYS_ENV="--env-file $P/staging.env --env-file $P/encryption.env"
NEW_ENV="--env-file $P/staging.env --env-file $P/encryption.env --env-file $P/woo.env"
state() {
  echo "schema_version=$(q 'select max(version) from schema_migrations') migrations=$(q 'select count(*) from schema_migrations')"
  echo "invalid_indexes=$(q 'select count(*) from pg_index where not indisvalid')"
  echo "whatsapp_provider_config_md5=$(q "select string_agg(md5(provider_config::text), ',' order by id) from channel_whatsapp")"
  echo "commerce_tables=$(q "select count(*) from information_schema.tables where table_name in ('commerce_stores','commerce_customer_links')")"
  echo "accounts=$(q 'select count(*) from accounts') conversations=$(q 'select count(*) from conversations') messages=$(q 'select count(*) from messages')"
}
harness() { # <image> <env> <label>
  run $1 "$2" "bundle exec rails runner /harness/check_existing_whatsapp.rb $3 2>&1 | tail -1" | tee -a $P/harness.log
}
t() { date -u +%s; }

echo "== 0. production before the release: $OLD on the pre-deploy backup"
redis-cli -n 13 flushdb >/dev/null
dropdb -h localhost -U postgres --if-exists $DB && createdb -h localhost -U postgres $DB
pg_restore -h localhost -U postgres -d $DB --no-owner $P/backup_pre_deploy.dump 2>&1 | tail -2
run $OLD "$BASE_ENV -e POSTGRES_STATEMENT_TIMEOUT=0" "bundle exec rails db:migrate" > $P/migrate_old.log 2>&1; echo "old migrate exit=$?"
state | tee $P/state_0_production.txt
harness $OLD "$BASE_ENV" p6_production_before

echo "== 1. backup"
pg_dump -h localhost -U postgres -Fc $DB > $P/backup_pre_commerce.dump
sha256sum $P/backup_pre_commerce.dump | tee $P/backup_pre_commerce.sha256

echo "== 2. migrate with the new image (encryption keys added to the environment)"
T0=$(t); run $NEW "$KEYS_ENV -e POSTGRES_STATEMENT_TIMEOUT=0" "bundle exec rails db:migrate" > $P/migrate_new.log 2>&1; echo "new migrate exit=$? seconds=$(( $(t) - T0 ))"
state | tee $P/state_2_deployed.txt
run $NEW "$KEYS_ENV" "bundle exec rails db:migrate:status 2>/dev/null | grep -c '^\s*down'" | sed 's/^/migrations_down=/'

echo "== 3. web + worker from the new image"
docker rm -f lyn6-web lyn6-worker >/dev/null 2>&1
docker run -d --name lyn6-web --network host $NEW_ENV $NEW bash -lc "bundle exec rails s -b 127.0.0.1 -p 3100" >/dev/null
docker run -d --name lyn6-worker --network host $NEW_ENV $NEW bash -lc "bundle exec sidekiq -C config/sidekiq.yml" >/dev/null
until curl -s -o /dev/null -w "%{http_code}" http://localhost:3100/app/login | grep -q 200; do sleep 3; done
ASSET=$(docker exec lyn6-web bash -lc "ls public/vite/assets | grep -m1 '\.js$'")
for probe in "GET /app/login" "GET /api" "GET /super_admin/sign_in" "GET /vite/assets/$ASSET" "POST /webhooks/shopify_commerce" "POST /webhooks/salla" \
             "POST /webhooks/zid/1" "GET /commerce/shopify/callback" "GET /commerce/zid/callback" "POST /webhooks/shopify"; do
  set -- $probe
  echo "$probe -> $(curl -s -o /dev/null -w '%{http_code}' -X $1 -H 'Content-Type: application/json' -d '{}' http://localhost:3100$2)"
done | tee $P/smoke_http.txt
sleep 5
echo "worker: $(docker logs lyn6-worker 2>&1 | grep -c -i 'booted\|starting processing') boot lines, running=$(docker inspect -f '{{.State.Running}}' lyn6-worker)" | tee -a $P/smoke_http.txt
(cd $P && mkdir -p ui && STAGING_APP_SECRET=staging-app-secret node rehearsal.js $P/ui > $P/ui.log 2>&1; tail -1 $P/ui.log)

echo "== 4. harness on the new image"
harness $NEW "$KEYS_ENV" p6_deployed
run $NEW "$KEYS_ENV" "bundle exec rails runner /harness/check_lynomia.rb p6_deployed 2>&1 | tail -1" | tee -a $P/harness.log
run $NEW "$KEYS_ENV" "bundle exec rails runner /harness/check_coexistence.rb p6_deployed 2>&1 | tail -1" | tee -a $P/harness.log
run $NEW "$NEW_ENV" "bundle exec rails runner /harness/check_commerce_switches.rb p6_deployed" > $P/commerce_switches.log 2>&1; tail -1 $P/commerce_switches.log
docker rm -f lyn6-web lyn6-worker >/dev/null

echo "== 5. rollback B: previous image on the migrated database (keys kept)"
T0=$(t); harness $OLD "$KEYS_ENV" p6_rollback_codeonly; echo "seconds=$(( $(t) - T0 ))"
docker run -d --name lyn6-web --network host $KEYS_ENV $OLD bash -lc "bundle exec rails s -b 127.0.0.1 -p 3100" >/dev/null
until curl -s -o /dev/null -w "%{http_code}" http://localhost:3100/app/login | grep -q 200; do sleep 3; done
echo "rollback B: /app/login $(curl -s -o /dev/null -w '%{http_code}' http://localhost:3100/app/login), /webhooks/shopify_commerce $(curl -s -o /dev/null -w '%{http_code}' -X POST http://localhost:3100/webhooks/shopify_commerce)" | tee -a $P/smoke_http.txt
docker rm -f lyn6-web >/dev/null
echo "commerce rows kept: stores=$(q 'select count(*) from commerce_stores')"

echo "== 6. rollback A: restore the backup + previous image"
T0=$(t)
dropdb -h localhost -U postgres $DB && createdb -h localhost -U postgres $DB
pg_restore -h localhost -U postgres -d $DB --no-owner $P/backup_pre_commerce.dump 2>&1 | tail -2
redis-cli -n 13 flushdb >/dev/null
state | tee $P/state_6_restored.txt
harness $OLD "$KEYS_ENV" p6_rollback_restore; echo "seconds=$(( $(t) - T0 ))"

echo "== 7. roll forward"
T0=$(t); run $NEW "$KEYS_ENV -e POSTGRES_STATEMENT_TIMEOUT=0" "bundle exec rails db:migrate" > $P/migrate_forward.log 2>&1; echo "migrate exit=$?"
state | tee $P/state_7_forward.txt
harness $NEW "$KEYS_ENV" p6_rollforward; echo "seconds=$(( $(t) - T0 ))"
echo "== 8. direct path: pre-4.18 backup migrated by the new image in one step (production not yet on e1cd4c53)"
dropdb -h localhost -U postgres $DB && createdb -h localhost -U postgres $DB
pg_restore -h localhost -U postgres -d $DB --no-owner $P/backup_pre_deploy.dump 2>&1 | tail -2
redis-cli -n 13 flushdb >/dev/null
T0=$(t); run $NEW "$KEYS_ENV -e POSTGRES_STATEMENT_TIMEOUT=0" "bundle exec rails db:migrate" > $P/migrate_direct.log 2>&1; echo "migrate exit=$? seconds=$(( $(t) - T0 ))"
state | tee $P/state_8_direct.txt
harness $NEW "$KEYS_ENV" p6_direct
echo "REHEARSAL DONE"
