#!/usr/bin/env bash
#
# The Documentation V2 / P0 regression gate.
#
# WHY THIS FILE EXISTS. The P0 hotfix phase ran its gate from a hand-written list of spec paths, one of which
# was `spec/controllers/public/api/v1/portals/` -- the DIRECTORY. The spec covering the public documentation
# home page is `spec/controllers/public/api/v1/portals_controller_spec.rb`, a sibling FILE one level above it.
# A change to Category#articles broke that page with a 500 and the gate stayed green, because the selection
# looked like it covered the area and did not. The two paths differ by one character.
#
# So this script never names a spec file. It DERIVES the list from the filesystem by subject, the same way the
# repository's own CI builds its list (.github/workflows/run_foss_spec.yml:131 `find spec -name '*_spec.rb'`),
# which means a spec file added anywhere under a matching subject is picked up with no edit here.
#
# Usage:  bash scripts/documentation_gate.sh            # derived subject suites
#         bash scripts/documentation_gate.sh --list     # print what it would run, run nothing
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

# Subject patterns, matched against the whole path of every *_spec.rb. Add a SUBJECT, never a file.
#   portal/article/categor  -- the documentation content model and every public portal surface
#   documentation           -- the Lynomia corpus, seeder, SEO audit and entry points
#   markdown_renderer       -- the render boundary the stored-XSS fix lives on
#   tenant_help_center      -- the tenant write-denial and isolation suite
#   search                  -- the one documentation read surface no policy guards
mapfile -t SPECS < <(
  find spec -name '*_spec.rb' \
    \( -path '*portal*' \
    -o -path '*article*' \
    -o -path '*categor*' \
    -o -path '*documentation*' \
    -o -path '*markdown_renderer*' \
    -o -path '*tenant_help_center*' \
    -o -path '*search*' \) | sort
)

if [ "${1:-}" = "--list" ]; then
  printf '%s\n' "${SPECS[@]}"
  echo "(${#SPECS[@]} spec files)"
  exit 0
fi

if [ ${#SPECS[@]} -eq 0 ]; then
  echo "documentation_gate: no spec files matched -- the patterns are wrong, failing rather than passing vacuously" >&2
  exit 1
fi

echo "documentation_gate: ${#SPECS[@]} spec files"
exec bundle exec rspec "${SPECS[@]}"
