#!/bin/bash
# Rollback rehearsal (docs/flow-builder/12-production-readiness.md §10): this release migrates a fresh database and
# leaves a published flow bot connected with a waiting session; the release before the Flow Builder (81ad706d2) runs on
# that database before and after the documented rollback steps (kill switch, hand over and detach, timers removed).
# usage: rehearse.sh <scratch_dir>   (scratch_dir holds commerce/e2e/e2e.env, the production-mode E2E environment)
S=${1:?scratch dir}
R=$(cd "$(dirname "$0")/../../.." && pwd); P=$R/docs/flow-builder/rollback; OLD=$S/rollback-old
rm -rf "${OLD:?}"; git -C "$R" worktree add -q --detach "$OLD" 81ad706d2
run() { # <tree> <command>
  docker run --rm --network host --env-file "$S/commerce/e2e/e2e.env" -e POSTGRES_DATABASE=lyn_rollback -e REDIS_URL=redis://localhost:6379/10 \
    -e DISABLE_DATABASE_ENVIRONMENT_CHECK=1 -e RAILS_LOG_TO_STDOUT=false -v "$1":/app -v "$P":/proof -v /app/node_modules -w /app \
    lynomia/verify:base bash -lc "$2" 2>&1 | grep -E "^(SEED|PASS|FAIL|STATE|SWITCH|DETACHED|enqueued|schema)|Error|error" | grep -v "RubyLLM"
}
echo "== 1. this release: schema, a published flow bot connected with a waiting session"
run "$R" "bundle exec rails db:drop db:create db:schema:load > /dev/null 2>&1; echo schema \$?; bundle exec rails runner /proof/seed_new.rb"
echo "== 2. the previous release on that database, flows still connected (what step C.2 prevents)"
run "$OLD" "bundle exec rails runner /proof/check_old.rb"
echo "== 3. this release: kill switch, hand over and detach, timers removed (§10 A, C.2, C.3)"
run "$R" "bundle exec rails runner /proof/detach_new.rb"
echo "== 4. the previous release after the documented steps"
run "$OLD" "bundle exec rails runner /proof/check_old.rb"
git -C "$R" worktree remove --force "$OLD"; git -C "$R" worktree prune
