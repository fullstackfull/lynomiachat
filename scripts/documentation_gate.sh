#!/usr/bin/env bash
#
# The Documentation V2 / P0 regression gate.
#
# WHY THIS FILE EXISTS, AND WHY IT HAS BEEN WRONG THREE TIMES.
#
# Round one: the gate ran from a hand-written list of spec paths, one of which was
# `spec/controllers/public/api/v1/portals/` -- the DIRECTORY. The spec covering the public documentation home
# page is `spec/controllers/public/api/v1/portals_controller_spec.rb`, a sibling FILE one level above it. A
# change to `Category#articles` broke that page with a 500 and the gate stayed green. So selection moved from a
# hand-written list to SUBJECT PATTERNS derived from the filesystem.
#
# Round two: subject patterns are also incomplete. Removing two providers from `config/markdown_embeds.yml`
# broke `spec/config/markdown_embeds_spec.rb` -- whose path contains `markdown_embeds`, which no subject matched
# (the pattern was `markdown_renderer`). The gate reported green and the breakage reached the mainline, where
# the repository's real CI runs every spec (`.github/workflows/run_foss_spec.yml:131` is
# `find spec -name '*_spec.rb'`).
#
# Round three (this revision): THE GATE RAN THE WRONG KIND OF THING. Both selectors pick rspec files, and rspec
# boots through `config/environment`, so three whole classes of breakage were structurally invisible to it:
#
#   - A `.rake` FILE THAT CANNOT LOAD. Wave 2 hoisted `include DocumentationHelper` to a class body inside
#     `lib/tasks/documentation_seo_audit.rake`. `Rakefile` is `require_relative 'config/application'` then
#     `load_tasks`, which never initializes the application, so Zeitwerk's autoloaders do not exist while a
#     `.rake` file is read: NameError out of `load_tasks`, which breaks EVERY rake task in the project --
#     `db:migrate` and `assets:precompile` among them, i.e. a failed deploy. It also killed
#     `maintain_test_schema!`, whose `bin/rails db:test:prepare` subprocess died on the same NameError. rspec
#     never loads a `.rake` file, so no spec could fail. A gate that cannot see a broken `load_tasks` cannot
#     see a broken deploy. -> PHASE A.
#   - A CONSTANT THAT ONLY FAILS WHEN EAGER LOADED. `config.eager_load_paths` carries `lib` and every
#     `custom/app/**` directory (config/application.rb:42,46), and `config.eager_load = false` in test
#     (config/environments/test.rb:16) while it is TRUE in production (config/environments/production.rb:11).
#     So a file that resolves lazily under rspec and raises at eager-load time breaks production BOOT with
#     every spec green. This is the same defect shape as the one above, one level over, and the fix for that
#     one -- moving a module into `lib/`, an eager load path -- is exactly what moved the risk here.
#     -> PHASE B.
#   - JAVASCRIPT. The changed-file selector explicitly excludes `app/javascript/`, and nothing ran vitest. The
#     program added an entire Super Admin editor there (`app/javascript/super_admin/documentation/**`, four
#     spec files) plus two dashboard registries, and all of it was verified by hand. A gate that cannot see the
#     editor's tests cannot see an editor regression. -> PHASE E.
#
# Two measured operating conditions, also from the Wave 3 integration record, are enforced rather than
# documented:
#
#   - TWO SUITES AGAINST `chatwoot_test` CONCURRENTLY produced 31 phantom failures (truncation and lock
#     interference). This script now takes an exclusive lock, so a second run refuses instead of corrupting
#     the first one's results. -> PHASE 0.
#   - A `documentation:*` RAKE RUN LEAVES ROWS that collide with `create(:portal, slug: 'lynomia-docs')`
#     ("Slug has already been taken"). A clean working tree is not a clean database. -> PHASE C.
#
# So the gate is five phases, cheapest and most fundamental first, and the rspec selection keeps its two
# independent selectors:
#
#   1. SUBJECT PATTERNS -- the documentation subsystem, by subject, derived from the filesystem.
#   2. CHANGED-FILE COVERAGE -- for every source file this branch changes, any spec file anywhere under spec/
#      whose basename matches it is ADDED to the run. No mapping table, no assumption about directory layout:
#      `config/markdown_embeds.yml` finds `spec/config/markdown_embeds_spec.rb` by name alone.
#
# Selector 2 deliberately OVER-selects (several specs can share a basename). Over-running is the correct bias
# for a gate; under-running is what shipped a 500 and a red mainline.
#
# Usage:  bash scripts/documentation_gate.sh            # run the gate
#         bash scripts/documentation_gate.sh --list     # print the plan and the selection, run nothing
#
# Env:    GATE_BASE_REF=<ref>   baseline for "changed files" (default: first of
#                               origin/lynomia-custom, lynomia-custom, origin/develop, develop that resolves)
#         RAILS_ENV             forced to `test` for every phase; rspec forces it anyway, and phases A and B
#                               must not run as `development`, where `lib/tasks/annotate_rb.rake:4` requires a
#                               gem this deployment installs only in that group (BUNDLE_WITHOUT=development).
#                               Measured: `rake -T` exits 1 on a LoadError there and 0 under test, and the
#                               `load_tasks` failure this phase exists to catch is environment-independent.
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

export RAILS_ENV=test
LIST_ONLY=false
[ "${1:-}" = "--list" ] && LIST_ONLY=true

# `git` refuses to read a repository owned by another user ("detected dubious ownership") and then every
# `rev-parse` fails. That is not hypothetical here: the database needs peer auth, so the suite is run as the
# `postgres` OS user against this root-owned tree, and in that shell the changed-file selector resolved no
# baseline and silently became subject-patterns-only. The exception is scoped to this repository.
GIT=(git -c "safe.directory=$PWD")

die() { echo "documentation_gate: $*" >&2; exit 1; }

phase() { echo; echo "documentation_gate: ===== $* ====="; }

# ---- Phase 0: one run at a time ---------------------------------------------------------------------------
LOCK_FILE="tmp/documentation_gate.lock"
mkdir -p tmp
if [ "$LIST_ONLY" = false ]; then
  exec 9>"$LOCK_FILE" || die "cannot open $LOCK_FILE"
  flock -n 9 || die "another gate run holds $LOCK_FILE. Two suites against one test database measured 31
  phantom failures (truncation and lock interference), so this refuses rather than producing a result nobody
  can trust. Wait for the other run."
fi

# ---- Selector 1: the documentation subsystem, by subject -------------------------------------------------
# Add a SUBJECT, never a file. `markdown` rather than `markdown_renderer`: the narrower token is what missed
# spec/config/markdown_embeds_spec.rb. `security` is here because spec/security/documentation_v2/** is the
# adversarial prefix -- its paths also match `documentation`, and it is named anyway so that moving those
# suites cannot quietly drop them.
# `*security/documentation_v2*` and not `*security*`: the bare token matched five unrelated suites (TikTok
# OAuth state, SMS webhooks, the flow runner), which is over-selection without coverage -- it adds runtime and
# unrelated reds for the integrator to triage, while covering nothing in this subsystem. `*media*` is likewise
# absent: every documentation media spec already matches `*documentation*` by its path, and the bare token only
# added the Twilio and WhatsApp media services.
SUBJECTS=(
  '*portal*' '*article*' '*categor*' '*documentation*' '*markdown*'
  '*tenant_help_center*' '*search*' '*security/documentation_v2*' '*text_direction*'
)
SUBJECT_FIND=()
for pattern in "${SUBJECTS[@]}"; do
  SUBJECT_FIND+=(-o -path "$pattern")
done
mapfile -t SUBJECT_SPECS < <(
  find spec -name '*_spec.rb' \( "${SUBJECT_FIND[@]:1}" \) | sort
)

# ---- Selector 2: whatever this branch changed ------------------------------------------------------------
resolve_base_ref() {
  if [ -n "${GATE_BASE_REF:-}" ]; then
    "${GIT[@]}" rev-parse --verify --quiet "$GATE_BASE_REF" >/dev/null && { echo "$GATE_BASE_REF"; return; }
    echo "documentation_gate: GATE_BASE_REF='$GATE_BASE_REF' does not resolve" >&2
    return 1
  fi
  for ref in origin/lynomia-custom lynomia-custom origin/develop develop; do
    "${GIT[@]}" rev-parse --verify --quiet "$ref" >/dev/null && { echo "$ref"; return; }
  done
  return 1
}

changed_paths() {
  { "${GIT[@]}" diff --name-only "$BASE_REF"...HEAD
    "${GIT[@]}" diff --name-only HEAD
    "${GIT[@]}" ls-files --others --exclude-standard
  } | sort -u
}

CHANGED_SPECS=()
CHANGED_JS_SPECS=()
CHANGED_SOURCES=()
CHANGED_JS_SOURCES=()
BASE_REF="$(resolve_base_ref)" || BASE_REF=""

if [ -z "$BASE_REF" ]; then
  # Loud, never silent: a gate that quietly drops a selector is the bug this selector exists to prevent.
  echo "documentation_gate: NO BASELINE REF RESOLVED -- changed-file coverage is NOT running." >&2
  echo "documentation_gate: subject patterns only. Set GATE_BASE_REF to restore full coverage." >&2
else
  # Ruby-side sources this branch touches, excluding specs themselves and the JS tree (vitest, not rspec).
  mapfile -t CHANGED_SOURCES < <(
    changed_paths \
      | grep -E '\.(rb|rake|yml|jbuilder|erb)$' \
      | grep -v '^spec/' \
      | grep -v '^app/javascript/'
  )
  # ...and the JS tree, which phase E covers and which selector 2 used to drop on the floor.
  mapfile -t CHANGED_JS_SOURCES < <(
    changed_paths \
      | grep -E '^app/javascript/.*\.(js|vue|ts)$' \
      | grep -v '\.spec\.'
  )

  # `${name%%.*}` strips EVERY extension, not just the last one. `_meta_head.html.erb` has to become
  # `meta_head`, not `meta_head.html`: a partial's basename carries two extensions, and the single-extension
  # form matched nothing at all -- so every changed view contributed zero specs to this selector. Measured on
  # `app/views/.../articles/_meta_head.html.erb`.
  spec_basenames_for() {
    local source stem
    for source in "$@"; do
      [ -n "$source" ] || continue
      stem="$(basename "$source")"
      stem="${stem%%.*}"           # markdown_embeds.yml -> markdown_embeds ; article.json.jbuilder -> article
      stem="${stem#_}"             # _meta_head.html.erb -> meta_head ; partials lead with an underscore
      [ -n "$stem" ] || continue
      echo "$stem"
    done
  }

  while IFS= read -r stem; do
    while IFS= read -r found; do
      CHANGED_SPECS+=("$found")
    done < <(find spec -name "${stem}_spec.rb")
  done < <(spec_basenames_for "${CHANGED_SOURCES[@]+"${CHANGED_SOURCES[@]}"}")

  while IFS= read -r stem; do
    while IFS= read -r found; do
      CHANGED_JS_SPECS+=("$found")
    done < <(find app/javascript -name "${stem}.spec.js" -o -name "${stem}.spec.ts")
  done < <(spec_basenames_for "${CHANGED_JS_SOURCES[@]+"${CHANGED_JS_SOURCES[@]}"}")
fi

# ---- Union, de-duplicated -------------------------------------------------------------------------------
mapfile -t SPECS < <(printf '%s\n' "${SUBJECT_SPECS[@]}" "${CHANGED_SPECS[@]+"${CHANGED_SPECS[@]}"}" | grep -v '^$' | sort -u)

# What selector 2 contributed that selector 1 would have missed -- printed so a miss is visible, not silent.
mapfile -t ONLY_FROM_CHANGES < <(
  comm -13 <(printf '%s\n' "${SUBJECT_SPECS[@]}" | sort -u) \
           <(printf '%s\n' "${CHANGED_SPECS[@]+"${CHANGED_SPECS[@]}"}" | grep -v '^$' | sort -u)
)

# ---- Phase E selection: the JS leg ----------------------------------------------------------------------
# Same two selectors, over vitest files. The subject list is the same one, because the subsystem is the same.
JS_SUBJECT_FIND=()
for pattern in "${SUBJECTS[@]}"; do
  JS_SUBJECT_FIND+=(-o -path "$pattern")
done
mapfile -t JS_SUBJECT_SPECS < <(
  find app/javascript \( -name '*.spec.js' -o -name '*.spec.ts' \) \( "${JS_SUBJECT_FIND[@]:1}" \) | sort
)
mapfile -t JS_SPECS < <(printf '%s\n' "${JS_SUBJECT_SPECS[@]}" "${CHANGED_JS_SPECS[@]+"${CHANGED_JS_SPECS[@]}"}" | grep -v '^$' | sort -u)

# ---- Coverage report: changed files that NEITHER selector covers ----------------------------------------
# Not a failure. Many files legitimately have no same-named spec -- a view, a layout, a migration. But the two
# rounds of wrongness above were both "the gate selected nothing for the thing that broke", and the only
# defence against a third is to print the list rather than let it be implicit. Read it: if something on it is
# load-bearing, it needs a spec or a subject pattern, not a greener gate.
uncovered() {
  local source stem covered
  for source in "$@"; do
    [ -n "$source" ] || continue
    stem="$(basename "$source")"; stem="${stem%%.*}"; stem="${stem#_}"
    covered="$(find spec app/javascript -name "${stem}_spec.rb" -o -name "${stem}.spec.js" 2>/dev/null | head -1)"
    [ -n "$covered" ] && continue
    printf '%s\n' "$source" | grep -qE '^(spec/|docs/|db/migrate/)' && continue
    echo "$source"
  done
}
mapfile -t UNCOVERED < <(uncovered \
  "${CHANGED_SOURCES[@]+"${CHANGED_SOURCES[@]}"}" "${CHANGED_JS_SOURCES[@]+"${CHANGED_JS_SOURCES[@]}"}")

print_selection() {
  printf '%s\n' "${SPECS[@]}"
  echo "(${#SPECS[@]} rspec files; ${#JS_SPECS[@]} vitest files; baseline ${BASE_REF:-NONE})"
  if [ ${#ONLY_FROM_CHANGES[@]} -gt 0 ]; then
    echo "added by changed-file coverage, not by any subject pattern:"
    printf '  %s\n' "${ONLY_FROM_CHANGES[@]}"
  fi
  if [ ${#JS_SPECS[@]} -gt 0 ]; then
    echo "vitest:"
    printf '  %s\n' "${JS_SPECS[@]}"
  fi
  if [ ${#UNCOVERED[@]} -gt 0 ]; then
    echo "CHANGED BUT COVERED BY NEITHER SELECTOR (${#UNCOVERED[@]}) -- no spec shares their basename:"
    printf '  %s\n' "${UNCOVERED[@]}"
  fi
}

if [ "$LIST_ONLY" = true ]; then
  echo "documentation_gate: phases -- A load_tasks, B eager load, C clean database, D rspec, E vitest"
  print_selection
  exit 0
fi

if [ ${#SPECS[@]} -eq 0 ]; then
  die "no spec files matched -- the patterns are wrong, failing rather than passing vacuously"
fi

# ---- Phase A: can `load_tasks` run at all? --------------------------------------------------------------
# `rake -T` is the whole mechanism: it reads every `.rake` file in the project before printing anything, and
# aborts on the first one that raises. Asserting that the project's OWN namespaces appear is the second half --
# an empty or truncated list would otherwise pass as "exit 0".
phase 'A: rake load_tasks'
RAKE_TASKS="$(bundle exec rake -T 2>&1)" || {
  echo "$RAKE_TASKS" >&2
  die "rake -T FAILED. Every rake task in this project is broken, db:migrate and assets:precompile included,
  so a deploy would fail. This is the defect class rspec structurally cannot see."
}
for required in 'documentation:content' 'documentation:setup' 'lynomia:docs:seo_audit'; do
  grep -q "^rake ${required}" <<<"$RAKE_TASKS" \
    || die "rake -T exited 0 but does not list '${required}'. A task file loaded without defining its tasks."
done
echo "documentation_gate: $(grep -c '^rake ' <<<"$RAKE_TASKS") tasks load, the documentation ones among them"

# ---- Phase B: does everything eager load? ---------------------------------------------------------------
# `zeitwerk:check` eager loads every autoload and eager-load path, which is what production does at boot and
# what the test environment never does. Measured at ~7s.
phase 'B: eager load (production boot shape)'
bundle exec rake zeitwerk:check 2>&1 | tail -1 | grep -q 'All is good' \
  || die "zeitwerk:check FAILED. Something in lib/ or custom/app/** resolves lazily under rspec and raises
  when eager loaded, which is a production BOOT failure with every spec green."

# ---- Phase C: is the database clean? --------------------------------------------------------------------
# A `documentation:*` run leaves rows, and `create(:portal, slug: 'lynomia-docs')` then fails with "Slug has
# already been taken" -- 31 phantom failures that look like a regression and are not. The gate refuses rather
# than truncating: destroying rows nobody asked it to destroy is not a gate's job, and in this program a
# populated test database has twice been an agent's in-flight measurement state.
phase 'C: clean test database'
COUNTS="$(bundle exec rails runner '
  media = ActiveStorage::Attachment.where(name: "documentation_media").count
  puts "articles=#{Article.count} categories=#{Category.count} portals=#{Portal.count} " \
       "super_admins=#{SuperAdmin.count} documentation_media=#{media}"
' 2>&1 | grep -E '^articles=')" || true
[ -n "$COUNTS" ] || die "could not read the test database. Phase C cannot be skipped: it is what stops a
  leftover 'lynomia-docs' portal from being reported as 31 regressions."
echo "documentation_gate: $COUNTS"
if grep -qE '=[1-9]' <<<"$COUNTS"; then
  die "the test database is NOT empty ($COUNTS). A clean tree is not a clean database: a documentation:* rake
  run leaves rows that collide with create(:portal, slug: 'lynomia-docs'). Reset it deliberately, then re-run:
      RAILS_ENV=test bundle exec rails db:test:prepare"
fi

# ---- Phase D: rspec ------------------------------------------------------------------------------------
phase "D: rspec -- ${#SPECS[@]} files (baseline ${BASE_REF:-NONE})"
if [ ${#ONLY_FROM_CHANGES[@]} -gt 0 ]; then
  echo "documentation_gate: ${#ONLY_FROM_CHANGES[@]} added by changed-file coverage: ${ONLY_FROM_CHANGES[*]}"
fi
if [ ${#UNCOVERED[@]} -gt 0 ]; then
  echo "documentation_gate: ${#UNCOVERED[@]} changed file(s) covered by NEITHER selector: ${UNCOVERED[*]}"
fi
bundle exec rspec "${SPECS[@]}" || die "rspec FAILED"

# ---- Phase E: vitest -----------------------------------------------------------------------------------
# Serialised after rspec on purpose (`nproc` = 4, orchestrator rule 5), and skipped LOUDLY rather than
# silently if the JS toolchain is not installed in this container -- the same precedent as the missing-baseline
# warning above, because a gate that quietly drops a leg is the defect this file keeps being revised for.
phase "E: vitest -- ${#JS_SPECS[@]} files"
if [ ${#JS_SPECS[@]} -eq 0 ]; then
  echo "documentation_gate: no JS spec matched the subjects -- nothing to run."
elif [ ! -x node_modules/.bin/vitest ]; then
  echo "documentation_gate: node_modules/.bin/vitest IS NOT INSTALLED -- the JS leg is NOT running." >&2
  echo "documentation_gate: the Super Admin editor's tests are unverified by this run. Run pnpm install." >&2
else
  node_modules/.bin/vitest run "${JS_SPECS[@]}" || die "vitest FAILED"
fi

echo
echo "documentation_gate: all phases passed"
