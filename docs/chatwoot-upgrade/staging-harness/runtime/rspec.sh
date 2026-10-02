#!/bin/bash
# Runs RSpec on the working tree in the verification image (verify.Dockerfile), prepared the way CI prepares it
# (.circleci/config.yml backend-tests, .github/workflows/run_foss_spec.yml): JavaScript dependencies installed from
# pnpm-lock.yaml before the suite, so the test asset build (ViteRuby autoBuild into public/vite-test, needed by every
# spec that renders a page) sees every dependency the tree declares. The image's own node_modules is a snapshot of the
# lockfile at the time the image was built; it is never used here.
#
#   rspec.sh <database> <redis_db> [rspec arguments]
#
#   SKIP_PREPARE=1      skip the dependency install and test asset build (already done for this tree, e.g. by the
#                       first of several shards run in parallel)
#   VERIFY_IMAGE        the image (default lynomia/verify:base)
#   VERIFY_DOCKER_ARGS  extra docker run arguments (for example a proxy and its CA for the package registry)
DB=${1:?database}; RDB=${2:?redis db}; shift 2
R=$(cd "$(dirname "$0")/../../../.." && pwd)
PREPARE="pnpm install --frozen-lockfile --ignore-scripts --reporter=append-only && bin/vite build --mode test"
[ "$SKIP_PREPARE" = "1" ] && PREPARE="true"
# shellcheck disable=SC2086
exec docker run --rm --network host $VERIFY_DOCKER_ARGS \
  -v "$R":/app -v lynomia_verify_node_modules:/app/node_modules \
  -e RAILS_ENV=test -e CI=true -e TZ=UTC -e POSTGRES_HOST=localhost -e POSTGRES_USERNAME=postgres \
  -e POSTGRES_PASSWORD=postgres -e POSTGRES_DATABASE="$DB" -e REDIS_URL="redis://localhost:6379/$RDB" \
  -w /app "${VERIFY_IMAGE:-lynomia/verify:base}" bash -lc \
  "set -e; $PREPARE; bundle exec rails db:create db:schema:load > /dev/null; bundle exec rspec $*"
