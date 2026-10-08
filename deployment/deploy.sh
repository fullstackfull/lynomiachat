#!/usr/bin/env bash
#
# Lynomia Chat production deploy.
#
# This replaces the unversioned /root/deploy-lynomia.sh. That script ran
#   git pull --ff-only && bundle install && db:migrate && pnpm vite build && systemctl restart chatwoot.target
# (docs/flow-builder/12-production-readiness.md:155) and was missing three steps, each of which has bitten or would
# bite a release:
#
#   1. pnpm install --frozen-lockfile  -- without it, the Vite build runs against stale node_modules and fails on any
#      release that adds a JavaScript dependency. Already recorded as a real failure in
#      docs/flow-builder/uat/README.md:38.
#   2. pnpm build:sdk  -- public/packs/js/sdk.js is the script customers embed on their own sites. It comes from its
#      own Vite pipeline (vite.lib.config.ts, pnpm build:sdk), NOT from `pnpm vite build`, and it is gitignored. So a
#      deploy that skips it leaves every customer site loading the previous widget indefinitely.
#   3. POSTGRES_STATEMENT_TIMEOUT=0 for the migration -- production sets a statement timeout, and a migration that
#      exceeds it is killed mid-flight. For CREATE INDEX CONCURRENTLY that leaves the index INVALID and the table
#      silently unindexed.
#
# It also takes a backup before touching the database, records the outgoing revision so a rollback has something to
# aim at, and verifies the services came back before reporting success.
#
# Run as root on the application server:   bash deployment/deploy.sh
#
# Behaviour on failure: stop immediately and do NOT restart. The previous version keeps serving. That is the one
# good property of the old script and it is preserved deliberately -- a half-deployed restart is worse than a
# postponed deploy.

set -Eeuo pipefail

APP_USER="${APP_USER:-chatwoot}"
APP_DIR="${APP_DIR:-/home/chatwoot/chatwoot}"
BACKUP_DIR="${BACKUP_DIR:-/var/backups/lynomia}"
TARGET="${TARGET:-chatwoot.target}"
HEALTH_URL="${HEALTH_URL:-http://127.0.0.1:3000/api}"
KEEP_BACKUPS="${KEEP_BACKUPS:-14}"

log()  { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
fail() { printf '\n\033[1;31m!!! %s\033[0m\n' "$*" >&2; exit 1; }
as_app() { sudo -u "$APP_USER" -H bash -lc "cd '$APP_DIR' && $1"; }

trap 'fail "deploy aborted at line $LINENO. Nothing was restarted; the previous version is still serving."' ERR

[[ $EUID -eq 0 ]] || fail "run as root: it restarts systemd units"
[[ -d $APP_DIR ]] || fail "$APP_DIR does not exist"

# ---------------------------------------------------------------------------
log "0. Pre-deploy checks"

if as_app 'git status --porcelain' | grep -q .; then
  fail "working tree at $APP_DIR is dirty. Commit, stash or revert first."
fi

PREVIOUS_SHA="$(as_app 'git rev-parse HEAD')"
PREVIOUS_BRANCH="$(as_app 'git rev-parse --abbrev-ref HEAD')"
echo "currently serving: $PREVIOUS_SHA ($PREVIOUS_BRANCH)"

systemctl is-active --quiet "$TARGET" || echo "note: $TARGET is not active before this deploy"

df -Pk "$APP_DIR" | awk 'NR==2 && $4 < 2097152 { print "less than 2GB free on the app filesystem"; exit 1 }' \
  || fail "not enough free disk for a build and a backup"

# ---------------------------------------------------------------------------
log "1. Fetch the release"

# Fetched and compared BEFORE the backup, so a no-op deploy costs nothing. It used to pull first and back up
# first, which meant every re-run of an already-deployed revision took a full pg_dump and then returned early --
# past the pruning at the end, so the directory grew unbounded on the one path most likely to be repeated.
as_app 'git fetch --quiet'
RELEASE_SHA="$(as_app 'git rev-parse @{u}')"

if [[ $RELEASE_SHA == "$PREVIOUS_SHA" ]]; then
  echo "already at $RELEASE_SHA; nothing to deploy"
  exit 0
fi
echo "deploying: $RELEASE_SHA"

# ---------------------------------------------------------------------------
log "2. Database backup"

install -d -m 750 -o "$APP_USER" -g "$APP_USER" "$BACKUP_DIR"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
DUMP="$BACKUP_DIR/$STAMP-pre-deploy-$PREVIOUS_SHA.dump"

# `.env` is a dotenv file, not a shell script, and production's is valid as the first and invalid as the second.
# `MAILER_SENDER_EMAIL=Lynomia <otp@lynomia.com>` is a redirection syntax error and
# `INSTALLATION_NAME=Lynomia Chat` runs `Chat` as a command, so the `set -a && . ./.env` this used to do aborted
# the backup on the real host. Sourcing was also the wrong tool in principle: the file is data, and evaluating it
# runs whatever it contains as root.
#
# Nor can dotenv do it for us. `Dotenv::Parser.call` performs variable AND command substitution on any value that
# is not single-quoted (substitutions/command.rb executes `$(...)` through backticks), so calling it would hand
# `.env` arbitrary code execution during the deploy, and `$VAR` would resolve differently depending on who ran it.
#
# So: take dotenv's own tokenizer -- `Dotenv::Parser::LINE`, the exact grammar the application reads this file
# with, so the dump authenticates with the same credentials the app does -- keep only the five PostgreSQL keys,
# run none of the substitutions, and refuse rather than guess if a value holds an unescaped `$`. `exec` then
# replaces ruby with pg_dump, so PGPASSWORD exists only in pg_dump's own environment, never in this script's and
# never in any argv.
as_app "bundle exec ruby - '$DUMP'" <<'PG_DUMP_WITH_DOTENV_CREDENTIALS'
require 'dotenv'

REQUIRED = %w[POSTGRES_DATABASE POSTGRES_USERNAME POSTGRES_PASSWORD].freeze
OPTIONAL = { 'POSTGRES_HOST' => 'localhost', 'POSTGRES_PORT' => '5432' }.freeze

abort 'no .env in the application directory, so the backup cannot read its credentials' unless File.exist?('.env')

found = {}
File.read('.env', encoding: 'BINARY').gsub(/\r\n?/, "\n").scan(Dotenv::Parser::LINE) do |key, value|
  next unless REQUIRED.include?(key) || OPTIONAL.key?(key)

  # dotenv's own value phase, minus the substitutions: strip a matching pair of surrounding quotes, then undo
  # backslash escapes unless the value was single-quoted. Later occurrences of a key win, as they do in dotenv.
  v = (value || '').strip
  quote = (v.length >= 2 && v[0] == v[-1] && %w[' "].include?(v[0])) ? v[0] : nil
  v = v[1..-2] if quote
  v = v.gsub(/\\([^$])/, '\1') unless quote == "'"
  found[key] = [v, quote]
end

found.each do |key, (value, quote)|
  next if quote == "'" || value !~ /(?<!\\)\$/

  abort "#{key} in .env holds an unescaped `$`. dotenv would expand a variable or run a command there, and the " \
        'result depends on which user and environment invoked it, so this backup will not guess which password ' \
        'it should use. Single-quote the value in .env to make it literal for the application and the backup alike.'
end

# dotenv emits a literal `$` for an escaped `\$`: both substitution passes drop the backslash and keep the rest
# (Variable#substitute returns `variable[1..]`, Command returns `$LAST_MATCH_INFO[0][1..]`). The check above has
# already established that every `$` still present is an escaped one, so this is the last thing left to match.
values = found.transform_values do |(value, quote)|
  quote == "'" ? value : value.gsub(/\\\$/, '$')
end
REQUIRED.each do |key|
  abort "#{key} is missing from .env, so the backup cannot run." if values[key].nil?
  abort "#{key} is blank in .env, so the backup cannot run." if values[key].strip.empty?
end
OPTIONAL.each { |key, default| values[key] = default if values[key].nil? || values[key].strip.empty? }

ENV['PGPASSWORD'] = values['POSTGRES_PASSWORD']
exec('pg_dump', '-Fc',
     '-h', values['POSTGRES_HOST'], '-p', values['POSTGRES_PORT'],
     '-U', values['POSTGRES_USERNAME'], values['POSTGRES_DATABASE'],
     '-f', ARGV.fetch(0))
PG_DUMP_WITH_DOTENV_CREDENTIALS

[[ -s $DUMP ]] || fail "backup is empty: $DUMP"
sha256sum "$DUMP" | tee "$DUMP.sha256"
echo "backup: $DUMP ($(du -h "$DUMP" | cut -f1))"

# ---------------------------------------------------------------------------
log "3. Check out the release"

as_app 'git merge --ff-only @{u}'
[[ "$(as_app 'git rev-parse HEAD')" == "$RELEASE_SHA" ]] || fail "working tree is not at $RELEASE_SHA after the fast-forward"
as_app 'git log --oneline -1'

# ---------------------------------------------------------------------------
log "4. Dependencies"

# BUNDLE_FROZEN refuses to rewrite Gemfile.lock. Without it an install that resolves differently from the
# committed lock succeeds, leaves the tree dirty, and the NEXT deploy fails at step 0 for a reason that looks
# unrelated. If this step fails, the fix is to resolve and commit the lock rather than to drop the flag.
as_app 'BUNDLE_FROZEN=true bundle install --quiet'
# Missing from the old script. Must run before any Vite build.
as_app 'pnpm install --frozen-lockfile'

# ---------------------------------------------------------------------------
log "5. Migrations"

# POSTGRES_STATEMENT_TIMEOUT=0 only for this step: production's timeout is there to protect request-path queries,
# and a migration is not a request. Without this a long index build is killed partway.
as_app 'RAILS_ENV=production POSTGRES_STATEMENT_TIMEOUT=0 bundle exec rails db:migrate'
# Two things the migration step can leave behind silently: a migration that did not run, and an index that a killed
# CREATE INDEX CONCURRENTLY left INVALID. Postgres keeps serving queries against an invalid index's table by
# sequential scan, so nothing fails -- it just gets slow, which is why this is checked rather than assumed.
as_app 'RAILS_ENV=production bundle exec rails runner "
  ActiveRecord::Migration.check_all_pending!
  invalid = ActiveRecord::Base.connection.select_values(
    %q(SELECT indexrelid::regclass::text FROM pg_index WHERE NOT indisvalid))
  abort(%q(invalid indexes present: ) + invalid.join(%q(, ))) if invalid.any?
  puts %q(schema ok)"'

# ---------------------------------------------------------------------------
log "6. Frontend build"

as_app 'NODE_OPTIONS=--max-old-space-size=4096 pnpm vite build'
as_app 'test -s public/vite/.vite/manifest.json' || fail "vite build produced no manifest"

# Missing from the old script: the embed script customers load from their own sites.
as_app 'NODE_OPTIONS=--max-old-space-size=4096 pnpm build:sdk'
as_app 'test -s public/packs/js/sdk.js' || fail "sdk build produced no public/packs/js/sdk.js"

# ---------------------------------------------------------------------------
log "7. Restart"

systemctl restart "$TARGET"

# ---------------------------------------------------------------------------
log "8. Verify"

for attempt in $(seq 1 30); do
  code="$(curl -fsS -o /tmp/deploy-readiness.json -w '%{http_code}' "$HEALTH_URL" || true)"
  [[ $code == 200 ]] && break
  [[ $attempt -eq 30 ]] && {
    echo "last readiness response:"; cat /tmp/deploy-readiness.json 2>/dev/null || true
    fail "readiness endpoint did not return 200 within 60s. ROLL BACK: see deployment/ROLLBACK.md, previous revision $PREVIOUS_SHA"
  }
  sleep 2
done
cat /tmp/deploy-readiness.json; echo

systemctl is-active --quiet "$TARGET" \
  || fail "$TARGET is not active after restart. ROLL BACK: previous revision $PREVIOUS_SHA"

for unit in chatwoot-web.1.service chatwoot-worker.1.service; do
  systemctl is-active --quiet "$unit" || fail "$unit is not active. ROLL BACK: previous revision $PREVIOUS_SHA"
done

as_app 'RAILS_ENV=production bundle exec rails runner "
  require %q(sidekiq/api)
  stats = Sidekiq::Stats.new
  puts %(sidekiq: enqueued=#{stats.enqueued} retry=#{stats.retry_size} dead=#{stats.dead_size} processes=#{Sidekiq::ProcessSet.new.size})
  abort(%q(no sidekiq process registered)) if Sidekiq::ProcessSet.new.size.zero?"'

# ---------------------------------------------------------------------------
log "9. Done"

printf 'deployed  %s -> %s\nbackup    %s\nrollback  previous revision %s (deployment/ROLLBACK.md)\n' \
  "$PREVIOUS_SHA" "$RELEASE_SHA" "$DUMP" "$PREVIOUS_SHA"

# Keep the backup directory from filling the disk, oldest first.
find "$BACKUP_DIR" -maxdepth 1 -name '*.dump' -printf '%T@ %p\n' | sort -rn | tail -n "+$((KEEP_BACKUPS + 1))" \
  | cut -d' ' -f2- | while read -r old; do rm -f -- "$old" "$old.sha256"; done

trap - ERR
