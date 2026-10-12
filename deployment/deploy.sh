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

# Two messages, because the right advice differs completely either side of the restart. RESTARTED is set to 1
# immediately after `systemctl restart`, and every failure after that point -- a readiness endpoint that never
# answers, a unit that did not come up, a Sidekiq process that did not register -- is a failure of the NEW code
# while the new code is serving. Telling the operator "nothing was restarted" there would send them looking in
# the wrong place at the worst moment.
RESTARTED=0
trap 'if [[ $RESTARTED -eq 1 ]]; then
        fail "deploy aborted at line $LINENO, AFTER the restart. The new revision $RELEASE_SHA is what is serving now and it is not healthy. ROLL BACK: see deployment/ROLLBACK.md, previous revision $PREVIOUS_SHA."
      else
        fail "deploy aborted at line $LINENO. Nothing was restarted; the previous version is still serving."
      fi' ERR

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

# Both filesystems, because they are usually different ones: the build writes under APP_DIR and the dump is
# written to BACKUP_DIR, which on this server's layout is /var/backups on the root filesystem. Measuring only
# APP_DIR passed a host with a full /var and then failed at the backup instead of before it. BACKUP_DIR may not
# exist yet on a first run, so its nearest existing parent is measured.
backup_fs_target="$BACKUP_DIR"
while [[ ! -d $backup_fs_target && $backup_fs_target != "/" ]]; do
  backup_fs_target="$(dirname "$backup_fs_target")"
done
df -Pk "$backup_fs_target" | awk -v d="$backup_fs_target" 'NR==2 && $4 < 2097152 { print "less than 2GB free on the backup filesystem (" d ")"; exit 1 }' \
  || fail "not enough free disk for the pre-deploy backup"
df -Pk "$APP_DIR" | awk 'NR==2 && $4 < 2097152 { print "less than 2GB free on the app filesystem"; exit 1 }' \
  || fail "not enough free disk for a build and a backup"

# ---------------------------------------------------------------------------
log "1. Fetch the release"

# Fetched and compared BEFORE the backup, so a no-op deploy costs nothing. It used to pull first and back up
# first, which meant every re-run of an already-deployed revision took a full pg_dump and then returned early --
# past the pruning at the end, so the directory grew unbounded on the one path most likely to be repeated.
as_app 'git fetch --quiet'
RELEASE_SHA="$(as_app 'git rev-parse @{u}')"

# The release is whatever the tracked upstream branch points at, which is right for an ordinary deploy and not
# enough for a controlled one: between the decision and the deploy, someone else can push. Set EXPECT_SHA to the
# revision that was actually reviewed and the deploy refuses anything else. Optional, so default behaviour is
# unchanged; docs/p-final/08-production-uat-runbook.md uses it for the combined release.
if [[ -n ${EXPECT_SHA:-} ]]; then
  if [[ $RELEASE_SHA != "$EXPECT_SHA"* ]]; then
    fail "upstream is at $RELEASE_SHA but EXPECT_SHA says $EXPECT_SHA. Nothing was changed. Push the intended revision, or correct EXPECT_SHA."
  fi
  echo "release matches EXPECT_SHA ($EXPECT_SHA)"
fi

# The working tree already being at the release is NOT the same as the release having been deployed. A deploy
# that failed anywhere after stage 3 -- a dependency install, a migration, the Vite build -- leaves the tree
# fast-forwarded and nothing else done, and the obvious operator response is to fix the cause and run the
# script again. Short-circuiting on the SHA alone answered that with "nothing to deploy" and exit 0, so the
# recovery path was to know to pass a flag that did not exist.
#
# The marker is what distinguishes the two. It is written only after stage 8 has verified the new revision is
# serving, so its absence means "this revision was checked out but never finished".
# In BACKUP_DIR, not under APP_DIR: stage 0 aborts on a dirty working tree, and an untracked marker file
# inside the repository is exactly that -- it would make the first deploy poison the second.
DEPLOYED_MARKER="$BACKUP_DIR/.last-deployed-sha"

if [[ $RELEASE_SHA == "$PREVIOUS_SHA" ]]; then
  if [[ -f $DEPLOYED_MARKER && "$(cat "$DEPLOYED_MARKER")" == "$RELEASE_SHA" ]]; then
    echo "already at $RELEASE_SHA and the last deploy of it completed; nothing to deploy"
    exit 0
  fi
  echo "tree is at $RELEASE_SHA but no completed deploy of it is recorded."
  echo "re-running the remaining stages: dependencies, migrations, build, restart, verify."
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

# Only the database name is genuinely required: `config/database.yml` reads POSTGRES_USERNAME and
# POSTGRES_PASSWORD with defaults, so an installation using peer authentication or a .pgpass file runs happily
# without either, and demanding them here aborted the backup -- and through the ERR trap the whole deploy -- on
# a host the application itself is fine with. The two credential keys fall back the way the application's own
# configuration falls back, and `pg_dump` then authenticates however the server is set up to let it.
REQUIRED = %w[POSTGRES_DATABASE].freeze
OPTIONAL = { 'POSTGRES_HOST' => 'localhost', 'POSTGRES_PORT' => '5432',
             'POSTGRES_USERNAME' => 'postgres', 'POSTGRES_PASSWORD' => nil }.freeze

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
OPTIONAL.each do |key, default|
  values[key] = default if values[key].nil? || values[key].to_s.strip.empty?
end

# Left unset rather than set to an empty string: an empty PGPASSWORD is a password attempt, which fails against
# a server expecting peer or ident authentication, where no variable at all succeeds.
#
# Plain Ruby, not `.present?`. This heredoc is a STANDALONE script -- `bundle exec ruby -` with one `require
# 'dotenv'` -- so Rails never loads and ActiveSupport is not available. `.present?` raised NoMethodError here on
# the real host, and because the backup runs under the ERR trap that aborted the whole deploy before anything had
# been changed. Loading ActiveSupport for one predicate would be the wrong fix: this block is deliberately the
# smallest thing that can read .env and exec pg_dump.
#
# `to_s.strip != ''` is the same answer `.present?` gave for the two values that can reach here -- nil, or a
# string -- and it is the same test the OPTIONAL loop above already uses, so the block now agrees with itself.
ENV['PGPASSWORD'] = values['POSTGRES_PASSWORD'] if values['POSTGRES_PASSWORD'].to_s.strip != ''
exec('pg_dump', '-Fc',
     '-h', values['POSTGRES_HOST'], '-p', values['POSTGRES_PORT'],
     '-U', values['POSTGRES_USERNAME'], values['POSTGRES_DATABASE'],
     '-f', ARGV.fetch(0))
PG_DUMP_WITH_DOTENV_CREDENTIALS

[[ -s $DUMP ]] || fail "backup is empty: $DUMP"

# Not just a size check. A truncated or corrupt custom-format dump is still a non-empty file, and the sha256
# below is a checksum OF WHATEVER WAS PRODUCED -- it proves the file has not changed since, never that it is
# restorable. `pg_restore -l` reads the archive's own table of contents, which is the cheapest thing that fails
# on a dump that cannot be restored, and it is the only verification standing between a bad deploy and an
# unrecoverable one. It reads the archive; it does not touch any database.
as_app "pg_restore -l '$DUMP' > /dev/null" \
  || fail "the backup at $DUMP is not a readable archive. Nothing was changed. Fix the backup before deploying."
TOC_ENTRIES="$(as_app "pg_restore -l '$DUMP' | grep -c '^[0-9]'" || echo 0)"
[[ ${TOC_ENTRIES:-0} -gt 0 ]] || fail "the backup at $DUMP lists no objects. Nothing was changed."

sha256sum "$DUMP" | tee "$DUMP.sha256"
echo "backup: $DUMP ($(du -h "$DUMP" | cut -f1), $TOC_ENTRIES objects in its table of contents)"

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
log "4b. libvips precondition"

# NEW IN THIS RELEASE, and a boot failure rather than a degradation. Rails moved 7.2.3.1 -> 7.2.3.2 to carry the
# fix for CVE-2026-66066, and that fix makes Active Storage REFUSE TO LOAD when it cannot disable libvips's
# unfuzzed operations -- it raises on `require` unless libvips is 8.13 or later AND ruby-vips is 2.2.1 or later
# (activestorage-7.2.3.2/lib/active_storage/vips.rb:34). The previous revision ran on ruby-vips 2.1.4, so the
# lockfile moves it to 2.3.0; the libvips half is a system package this script cannot install.
#
# Every Rails process aborts, web and worker alike, so an old libvips on this host turns the restart at stage 7
# into an outage with no rollback of its own. Checked here because stage 5 boots Rails too: left unchecked the
# deploy dies in the middle of the migrations with an Active Storage backtrace and no statement of the cause.
# This is after the backup and before any schema change, so a failure here costs one unused dump and nothing
# else.
as_app 'RAILS_ENV=production bundle exec rails runner "
  require %q(vips)
  puts %Q(libvips #{[Vips.version(0), Vips.version(1), Vips.version(2)].join(%q(.))}, ruby-vips #{Vips::VERSION})"' \
  || fail "libvips precondition not met. Active Storage in Rails 7.2.3.2 needs libvips >= 8.13 and ruby-vips >= 2.2.1. Nothing has been migrated. Upgrade libvips on this host (Debian/Ubuntu: apt-get install --only-upgrade libvips42) and re-run."

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
log "6b. Quiet the workers and let the in-flight set drain"

# Sidekiq is told to stop taking new work, then given up to 60s to finish what it is holding, BEFORE the
# restart. Two reasons, one general and one specific to this release:
#
#   * A restart under load kills jobs mid-flight. Sidekiq pushes an interrupted job back for retry, so the work
#     is not lost, but a job that had already made a provider call is retried from the top -- which for a
#     campaign send means a second WhatsApp message to a real person.
#   * This release DELETES Campaigns::UpdateRecipientStatusJob, which the previous revision enqueued with a
#     two-second delay and up to five retries. Instances therefore sit in the scheduled and retry sets at the
#     moment of the restart, and after it each one raises NameError until it reaches the dead set. Draining
#     first means the old code consumes its own jobs (docs/p-final/03-migration-review.md section 8.1).
#
# `sidekiqctl quiet` is addressed through systemctl because the units own the processes: TSTP is Sidekiq's
# documented quiet signal and SIGTERM its graceful stop, so this is the signal pair the gem expects.
if systemctl is-active --quiet chatwoot-worker.1.service; then
  systemctl kill --signal=SIGTSTP chatwoot-worker.1.service \
    || echo "note: could not quiet chatwoot-worker.1.service; continuing"
fi

# The probe's own failure is not a drain. The first version of this loop sent stderr to /dev/null and fell back
# to `echo 0`, so a Redis refusal or a `rails runner` exception produced "0" and the loop announced
# "in-flight set drained" -- the one reading this stage exists to rule out. A probe that cannot answer is
# reported as unknown and the loop keeps asking.
#
# WHY A SENTINEL RATHER THAN THE WHOLE OF STDOUT. The second version required the entire captured output to
# match `^[0-9]+$`. On the real host it never did: `as_app` runs a LOGIN shell, so Dotenv, RubyLLM and Sidekiq
# each printed an informational line to stdout alongside the number. A genuine empty in-flight set was
# therefore read as unreadable, and with REQUIRE_DRAIN set that stopped a deploy whose workers had in fact
# drained -- the opposite of the failure the version before it had.
#
# So `rails runner` now prints ONE machine-readable line and the shell reads only that line. The contract:
#
#   * The Ruby below prints `__LYNOMIA_BUSY__=<n>` on a line of its own. The literal is repeated in the sed
#     expression two lines down; the two must stay in step.
#   * `sed -n 's/^__LYNOMIA_BUSY__=\([0-9][0-9]*\)$/\1/p'` yields the integer from every line matching the
#     grammar EXACTLY, and nothing from any other line. Anything printed before or after it is ignored.
#   * EXACTLY ONE such line is required. None means the probe did not answer; two or more means it answered
#     twice and this stage will not pick a winner. Either way the result is unknown.
#   * A non-zero `rails runner` status is unknown, whatever it printed.
#   * Unknown is never zero. `busy` stays empty, `drained` stays 0, and the REQUIRE_DRAIN decision below is
#     reached exactly as it was before.
#
# stderr is deliberately NOT captured: it stays on the operator's terminal where a Redis refusal is visible,
# and it cannot reach the parser.
drained=0
for attempt in $(seq 1 30); do
  # The status is kept rather than swallowed: `|| probe_status=$?` is what keeps `set -e` from aborting the
  # deploy on a probe that simply could not run, which is a condition this loop is built to tolerate.
  probe_status=0
  probe_out="$(as_app 'RAILS_ENV=production bundle exec rails runner "
    require %q(sidekiq/api); puts %(__LYNOMIA_BUSY__=#{Sidekiq::Stats.new.workers_size})"')" || probe_status=$?

  busy=''
  sentinel_values=()
  if [[ $probe_status -eq 0 ]]; then
    mapfile -t sentinel_values < <(printf '%s\n' "$probe_out" | sed -n 's/^__LYNOMIA_BUSY__=\([0-9][0-9]*\)$/\1/p')
    [[ ${#sentinel_values[@]} -eq 1 ]] && busy="${sentinel_values[0]}"
  fi

  if [[ -n $busy ]]; then
    # Base 10 explicitly: `workers_size` prints no leading zeros, but `[[ 08 -eq 0 ]]` is an arithmetic error
    # rather than a comparison, and this line must not be the one that aborts a deploy.
    if (( 10#$busy == 0 )); then
      echo "sidekiq: in-flight set drained"
      drained=1
      break
    fi
    echo "sidekiq: $((10#$busy)) busy worker(s)"
  else
    echo "note: could not read sidekiq's in-flight set (attempt $attempt/30, probe exit $probe_status, \
${#sentinel_values[@]} sentinel line(s))"
    # Once, on the last attempt: what the probe actually said. This is the evidence that diagnosed the bug
    # above, and printing it turns the next occurrence into a one-deploy diagnosis.
    if [[ $attempt -eq 30 ]]; then
      echo "      the probe's last stdout was:"
      printf '%s\n' "$probe_out" | head -n 20 | sed 's/^/      | /'
    fi
  fi
  sleep 2
done

# Not a `fail`: the operator decides. Stopping here leaves the release checked out and migrated with the old
# code still serving, which is a coherent state to hold; restarting anyway risks the double send stage 6b
# exists to prevent. REQUIRE_DRAIN=1 turns the judgement call into a refusal for a deploy that must not take
# that risk unattended. docs/p-final/08-production-uat-runbook.md states what to do when this line appears.
if [[ $drained -eq 0 ]]; then
  if [[ -n ${REQUIRE_DRAIN:-} ]]; then
    fail "sidekiq did not confirm an empty in-flight set within 60s and REQUIRE_DRAIN is set. The release is checked out and migrated; the OLD code is still serving. See docs/p-final/08-production-uat-runbook.md section 16."
  fi
  echo "WARNING: sidekiq did not confirm an empty in-flight set within 60s. Restarting anyway."
  echo "         A job that had already called a provider will be retried from the top after the restart."
  echo "         See docs/p-final/08-production-uat-runbook.md section 16."
fi

# ---------------------------------------------------------------------------
log "7. Restart"

systemctl restart "$TARGET"
# From here on a failure means the new code is serving and is not healthy, which the ERR trap says instead.
RESTARTED=1

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

# Written here and nowhere else: stage 8 has just confirmed the new revision is serving and healthy, so this
# file is the record that distinguishes "this revision is deployed" from "this revision is merely checked out".
# Stage 1 reads it to decide whether a re-run is a no-op or a resumption.
printf '%s\n' "$RELEASE_SHA" > "$DEPLOYED_MARKER"

printf 'deployed  %s -> %s\nbackup    %s\nrollback  previous revision %s (deployment/ROLLBACK.md)\n' \
  "$PREVIOUS_SHA" "$RELEASE_SHA" "$DUMP" "$PREVIOUS_SHA"

# Keep the backup directory from filling the disk, oldest first.
find "$BACKUP_DIR" -maxdepth 1 -name '*.dump' -printf '%T@ %p\n' | sort -rn | tail -n "+$((KEEP_BACKUPS + 1))" \
  | cut -d' ' -f2- | while read -r old; do rm -f -- "$old" "$old.sha256"; done

trap - ERR
