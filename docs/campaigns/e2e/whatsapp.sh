#!/bin/bash
# Runs the Campaigns WhatsApp E2E (docs/campaigns/07-e2e.md) on a fresh production-mode harness database: the staging
# harness seed (Tenant A's WhatsApp Cloud number, Tenant B), then check_campaigns_whatsapp.rb. Meta is FakeGraph.
# usage: whatsapp.sh <out_dir> <scratch_dir>   (scratch_dir holds commerce/e2e/e2e.env)
OUT=$1; S=$2
R=$(cd "$(dirname "$0")/../../.." && pwd)
H=docs/chatwoot-upgrade/staging-harness
mkdir -p "${OUT:?}" "${R:?}/${H:?}/out"
docker run --rm --network host --env-file "${S:?}/commerce/e2e/e2e.env" -e POSTGRES_DATABASE=lyn_harness_campaign \
  -e REDIS_URL=redis://localhost:6379/8 -e RAILS_LOG_TO_STDOUT=false -e DISABLE_DATABASE_ENVIRONMENT_CHECK=1 -e FRONTEND_URL=https://staging.lynomia.local \
  -v "$R":/app -v lyn_nm:/app/node_modules -w /app lynomia/verify:base bash -lc "
  bundle exec rails db:drop db:create db:schema:load > /app/$H/out/campaign_setup.log 2>&1; echo schema \$?
  bundle exec rails runner $H/seed_pre_upgrade.rb > /app/$H/out/campaign_seed.log 2>&1; echo seed \$?
  bundle exec rails runner docs/campaigns/e2e/check_campaigns_whatsapp.rb 2>&1 | grep -v 'RubyLLM\|^W, \|^I, \|^\$'"
mv "${R:?}/${H:?}/out/"* "${OUT:?}/"
rmdir "${R:?}/${H:?}/out"
