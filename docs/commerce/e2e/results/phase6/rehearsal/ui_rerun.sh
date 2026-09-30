#!/bin/bash
# UI smoke on the new image, after the rehearsal (the pre-deploy backup has no Super Admin: one is created as test data).
S=$SCRATCH; P=$S/p6/rehearsal
NEW=lynomia/staging:final-f842e12e
set -a; . $P/ui.env; set +a
ENVS="--env-file $P/staging.env --env-file $P/encryption.env"
docker run --rm --network host $ENVS -e STAGING_COMMERCE_SECRET $NEW bash -lc "bundle exec rails runner '
  SuperAdmin.find_or_initialize_by(email: %q(superadmin@staging.lynomia.local)).tap { |u| u.update!(name: %q(Super Admin), password: %q(Password1!x), confirmed_at: Time.current) }
  %w[SALLA_CLIENT_SECRET ZID_CLIENT_SECRET SHOPIFY_COMMERCE_CLIENT_SECRET].each { |n| InstallationConfig.find_or_initialize_by(name: n).update!(value: ENV.fetch(%q(STAGING_COMMERCE_SECRET)), locked: false) }
  puts [%q(setup), SuperAdmin.count, InstallationConfig.find_by(name: %q(WHATSAPP_APP_SECRET)).present?, Commerce::Providers.enabled.inspect].join(%q( ))
' 2>&1 | tail -1"
docker rm -f lyn6-web >/dev/null 2>&1
docker run -d --name lyn6-web --network host $ENVS $NEW bash -lc "bundle exec rails s -b 127.0.0.1 -p 3100" >/dev/null
until curl -s -o /dev/null -w "%{http_code}" http://localhost:3100/app/login | grep -q 200; do sleep 3; done
rm -rf $P/ui && mkdir -p $P/ui
(cd $P && STAGING_APP_SECRET=staging-app-secret node rehearsal.js $P/ui > $P/ui.log 2>&1; tail -1 $P/ui.log)
docker logs lyn6-web > $P/ui_web.log 2>&1
docker rm -f lyn6-web >/dev/null
