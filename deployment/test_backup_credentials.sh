#!/usr/bin/env bash
#
# Shell-level checks for the pre-deploy backup's credential block in deploy.sh (stage 2).
#
# Run:  bash deployment/test_backup_credentials.sh
#
# WHY THIS EXISTS. That block is a STANDALONE ruby script -- `bundle exec ruby -` fed by a heredoc, with one
# `require 'dotenv'`. Rails never loads, so ActiveSupport is not there. It nevertheless called `.present?`,
# which raised NoMethodError on the real host; because the backup runs under the ERR trap, that aborted the
# whole deploy. Nothing had been changed at that point, so the failure was safe -- but it was only ever going
# to be found in production, because this block runs nowhere else.
#
# These cases run it anywhere. The block is extracted VERBATIM from deploy.sh; a copy would drift.
#
# The only thing replaced is `exec`, which would otherwise replace the process with pg_dump. Overriding
# Kernel#exec leaves every line of the block itself untouched and makes its one effect -- whether PGPASSWORD
# ends up in the environment pg_dump would inherit -- observable.
set -Eeuo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
DEPLOY="$HERE/deploy.sh"
[[ -r $DEPLOY ]] || { echo "cannot read $DEPLOY" >&2; exit 1; }

# The block needs the application's own bundle for dotenv, and the application's own Ruby: chdir'ing to a
# fixture directory takes us out of reach of .ruby-version, which silently selects a different interpreter.
command -v rbenv > /dev/null && eval "$(rbenv init -)"
[[ -r $REPO/.ruby-version ]] && export RBENV_VERSION="$(cat "$REPO/.ruby-version")"
export BUNDLE_GEMFILE="$REPO/Gemfile"

if ! bundle exec ruby -e "require 'dotenv'" > /dev/null 2>&1; then
  echo "SKIP: this host cannot load the application bundle's dotenv, so the backup block cannot be run here."
  echo "      The parsing checks below need it; run them on a host with the bundle installed."
  exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

awk "/<<'PG_DUMP_WITH_DOTENV_CREDENTIALS'/ { inside = 1; next }
     /^PG_DUMP_WITH_DOTENV_CREDENTIALS\$/   { inside = 0 }
     inside" "$DEPLOY" > "$WORK/block.rb"
[[ -s $WORK/block.rb ]] || { echo "could not extract the backup block from deploy.sh" >&2; exit 1; }

cat > "$WORK/run.rb" <<'RUNNER'
module Kernel
  def exec(*args)
    puts "PGPASSWORD=#{ENV.key?('PGPASSWORD') ? ENV['PGPASSWORD'].inspect : '<unset>'}"
    exit 0
  end
end
ARGV.replace(['/dev/null'])
load ENV.fetch('BLOCK_PATH')
RUNNER

PASS=0
FAIL=0

# The whole point: the block must reach its decision WITHOUT ActiveSupport. Any `.present?`, `.blank?` or
# `.presence` that creeps back in raises NoMethodError here rather than on the production host.
echo
echo 'The block must not depend on ActiveSupport'
if grep -vE '^\s*#' "$WORK/block.rb" | grep -qE '\.(present\?|blank\?|presence)'; then
  echo '  FAIL  an ActiveSupport predicate is back in the block'
  FAIL=$((FAIL + 1))
else
  echo '  ok    no ActiveSupport predicate in the block'
  PASS=$((PASS + 1))
fi

check() {
  local name="$1" env_body="$2" want="$3"
  local dir="$WORK/case"
  rm -rf "$dir"; mkdir -p "$dir"
  printf '%s\n' "$env_body" > "$dir/.env"

  # `|| true` deliberately: a block that RAISES is a failing case to report, not a reason to kill the run.
  # Without it `set -e` plus `pipefail` aborts here, and the one regression this file exists to catch -- an
  # ActiveSupport predicate creeping back in -- would end the harness instead of being printed.
  local got
  got="$(cd "$dir" && BLOCK_PATH="$WORK/block.rb" bundle exec ruby "$WORK/run.rb" 2>&1 | head -1)" || true

  if [[ $got == "$want" ]]; then
    printf '  ok    %s\n' "$name"
    PASS=$((PASS + 1))
  else
    printf '  FAIL  %s\n        want: %s\n        got:  %s\n' "$name" "$want" "$got"
    FAIL=$((FAIL + 1))
  fi
}

echo
echo 'PGPASSWORD is set only for a password that is really there'
# Unset, not empty: an empty PGPASSWORD is a password ATTEMPT, which fails against a server expecting peer or
# ident authentication -- where no variable at all succeeds. This is the distinction `.present?` was making.
check 'no password key at all (peer authentication)' \
  'POSTGRES_DATABASE=lyn' 'PGPASSWORD=<unset>'

check 'password present but empty' \
  'POSTGRES_DATABASE=lyn
POSTGRES_PASSWORD=' 'PGPASSWORD=<unset>'

check 'password is whitespace only' \
  "POSTGRES_DATABASE=lyn
POSTGRES_PASSWORD='   '" 'PGPASSWORD=<unset>'

check 'password present' \
  'POSTGRES_DATABASE=lyn
POSTGRES_PASSWORD=s3cret' 'PGPASSWORD="s3cret"'

# `strip` is the blankness TEST, never applied to the value: a password whose surrounding spaces are real
# still reaches pg_dump intact. Stripping it would authenticate with a different password than the app uses.
check 'password whose surrounding spaces are meaningful' \
  "POSTGRES_DATABASE=lyn
POSTGRES_PASSWORD=' pad '" 'PGPASSWORD=" pad "'

echo
printf '%s passed, %s failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
