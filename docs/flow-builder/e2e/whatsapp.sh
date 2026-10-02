#!/bin/bash
# Runs the Flow Builder WhatsApp E2E (docs/flow-builder/10-e2e.md) on a fresh production-mode harness database: the
# staging harness seed (Tenant A's WhatsApp Cloud number, Tenant B), then scenarios A–E. The WooCommerce test store's
# Read key is passed in an env file, never on a command line or in the output.
# usage: whatsapp.sh <out_dir> <scratch_dir>   (scratch_dir holds commerce/e2e/e2e.env and commerce/woo/key.txt)
OUT=$1; S=$2
R=$(cd "$(dirname "$0")/../../.." && pwd)
H=docs/chatwoot-upgrade/staging-harness
mkdir -p "${OUT:?}" "${R:?}/${H:?}/out"
K=($(cat "${S:?}/commerce/woo/key.txt")); umask 077; printf 'WOO_CK=%s\nWOO_CS=%s\n' "${K[0]}" "${K[1]}" > "${OUT:?}/woo.env"; unset K
docker run --rm --network host --env-file "$S/commerce/e2e/e2e.env" --env-file "$OUT/woo.env" -e POSTGRES_DATABASE=lyn_harness_flow \
  -e REDIS_URL=redis://localhost:6379/14 -e RAILS_LOG_TO_STDOUT=false -e DISABLE_DATABASE_ENVIRONMENT_CHECK=1 -e FRONTEND_URL=https://staging.lynomia.local \
  -v "$R":/app -v lyn_nm:/app/node_modules -w /app lynomia/verify:base bash -lc "
  bundle exec rails db:drop db:create db:schema:load > /app/$H/out/flow_setup.log 2>&1; echo schema \$?
  bundle exec rails runner $H/seed_pre_upgrade.rb > /app/$H/out/flow_seed.log 2>&1; echo seed \$?
  bundle exec rails runner docs/flow-builder/e2e/check_flows_whatsapp.rb 2>&1 | grep -v 'RubyLLM\|^W, \|^I, \|^\$'"
rm -f "${OUT:?}/woo.env"
mv "${R:?}/${H:?}/out/"* "${OUT:?}/"
rmdir "${R:?}/${H:?}/out"
