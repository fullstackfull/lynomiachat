#!/bin/bash
# (Re)starts the Automation E2E's job worker (docs/automation/08-e2e.md): Sidekiq, as in production, on the E2E
# production environment. `private-network` adds SAFE_FETCH_ALLOW_PRIVATE_NETWORK=true, the existing switch an operator
# sets to deliver webhooks to a self-hosted n8n on a private network; `default` leaves the SSRF guard as shipped.
# usage: worker.sh <default|private-network> <scratch_dir>
MODE=$1; S=$2
R=$(cd "$(dirname "$0")/../../.." && pwd)
E=$S/commerce/e2e
LOG=$R/tmp/e2e_worker.log
EXTRA=()
[ "$MODE" = private-network ] && EXTRA=(-e SAFE_FETCH_ALLOW_PRIVATE_NETWORK=true)
docker rm -f lyn-auto-worker >/dev/null 2>&1
touch "$LOG"; FROM=$(($(wc -l < "$LOG") + 1))
echo "== e2e worker: $MODE ==" >> "$LOG"
docker run -d --name lyn-auto-worker --network host --env-file $E/e2e.env "${EXTRA[@]}" -v $R:/app -v lyn_nm:/app/node_modules -w /app \
  lynomia/verify:base bash -lc "bundle exec sidekiq -C config/sidekiq.yml >> /app/tmp/e2e_worker.log 2>&1" >/dev/null
until tail -n +$FROM "$LOG" | grep -q "Booted Rails"; do sleep 2; done; sleep 3
