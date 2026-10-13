#!/usr/bin/env bash
#
# The Documentation V2 / P0 regression gate.
#
# WHY THIS FILE EXISTS, AND WHY IT HAS BEEN WRONG TWICE.
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
# So this script now has TWO independent selectors, and the second does not depend on anyone choosing a good
# pattern:
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
#         bash scripts/documentation_gate.sh --list     # print what it would run, run nothing
#
# Env:    GATE_BASE_REF=<ref>   baseline for "changed files" (default: first of
#                               origin/lynomia-custom, lynomia-custom, origin/develop, develop that resolves)
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

# ---- Selector 1: the documentation subsystem, by subject -------------------------------------------------
# Add a SUBJECT, never a file. `markdown` rather than `markdown_renderer`: the narrower token is what missed
# spec/config/markdown_embeds_spec.rb.
mapfile -t SUBJECT_SPECS < <(
  find spec -name '*_spec.rb' \
    \( -path '*portal*' \
    -o -path '*article*' \
    -o -path '*categor*' \
    -o -path '*documentation*' \
    -o -path '*markdown*' \
    -o -path '*tenant_help_center*' \
    -o -path '*search*' \) | sort
)

# ---- Selector 2: whatever this branch changed ------------------------------------------------------------
resolve_base_ref() {
  if [ -n "${GATE_BASE_REF:-}" ]; then
    git rev-parse --verify --quiet "$GATE_BASE_REF" >/dev/null && { echo "$GATE_BASE_REF"; return; }
    echo "documentation_gate: GATE_BASE_REF='$GATE_BASE_REF' does not resolve" >&2
    return 1
  fi
  for ref in origin/lynomia-custom lynomia-custom origin/develop develop; do
    git rev-parse --verify --quiet "$ref" >/dev/null && { echo "$ref"; return; }
  done
  return 1
}

CHANGED_SPECS=()
BASE_REF="$(resolve_base_ref)" || BASE_REF=""

if [ -z "$BASE_REF" ]; then
  # Loud, never silent: a gate that quietly drops a selector is the bug this selector exists to prevent.
  echo "documentation_gate: NO BASELINE REF RESOLVED -- changed-file coverage is NOT running." >&2
  echo "documentation_gate: subject patterns only. Set GATE_BASE_REF to restore full coverage." >&2
else
  # Source files this branch touches, excluding specs themselves and the JS tree (vitest, not rspec).
  mapfile -t CHANGED_SOURCES < <(
    { git diff --name-only "$BASE_REF"...HEAD; git diff --name-only HEAD; git ls-files --others --exclude-standard; } \
      | sort -u \
      | grep -E '\.(rb|rake|yml|jbuilder|erb)$' \
      | grep -v '^spec/' \
      | grep -v '^app/javascript/'
  )

  for source in "${CHANGED_SOURCES[@]}"; do
    [ -n "$source" ] || continue
    stem="$(basename "$source")"
    stem="${stem%.*}"            # markdown_embeds.yml  -> markdown_embeds
    stem="${stem#_}"             # _article.json.jbuilder -> article.json ; partials lead with _
    stem="${stem%.json}"         # article.json          -> article
    [ -n "$stem" ] || continue
    while IFS= read -r found; do
      CHANGED_SPECS+=("$found")
    done < <(find spec -name "${stem}_spec.rb")
  done
fi

# ---- Union, de-duplicated -------------------------------------------------------------------------------
mapfile -t SPECS < <(printf '%s\n' "${SUBJECT_SPECS[@]}" "${CHANGED_SPECS[@]+"${CHANGED_SPECS[@]}"}" | grep -v '^$' | sort -u)

# What selector 2 contributed that selector 1 would have missed -- printed so a miss is visible, not silent.
mapfile -t ONLY_FROM_CHANGES < <(
  comm -13 <(printf '%s\n' "${SUBJECT_SPECS[@]}" | sort -u) \
           <(printf '%s\n' "${CHANGED_SPECS[@]+"${CHANGED_SPECS[@]}"}" | grep -v '^$' | sort -u)
)

if [ "${1:-}" = "--list" ]; then
  printf '%s\n' "${SPECS[@]}"
  echo "(${#SPECS[@]} spec files; baseline ${BASE_REF:-NONE})"
  if [ ${#ONLY_FROM_CHANGES[@]} -gt 0 ]; then
    echo "added by changed-file coverage, not by any subject pattern:"
    printf '  %s\n' "${ONLY_FROM_CHANGES[@]}"
  fi
  exit 0
fi

if [ ${#SPECS[@]} -eq 0 ]; then
  echo "documentation_gate: no spec files matched -- the patterns are wrong, failing rather than passing vacuously" >&2
  exit 1
fi

echo "documentation_gate: ${#SPECS[@]} spec files (baseline ${BASE_REF:-NONE})"
if [ ${#ONLY_FROM_CHANGES[@]} -gt 0 ]; then
  echo "documentation_gate: ${#ONLY_FROM_CHANGES[@]} added by changed-file coverage: ${ONLY_FROM_CHANGES[*]}"
fi
exec bundle exec rspec "${SPECS[@]}"
