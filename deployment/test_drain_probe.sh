#!/usr/bin/env bash
#
# Shell-level checks for the Sidekiq drain probe in deploy.sh (stage 6b).
#
# Run:  bash deployment/test_drain_probe.sh
#
# WHY THIS EXISTS. The probe has now been wrong in production twice, in opposite directions:
#
#   1. It fell back to `echo 0` when it could not read the in-flight set, so a Redis refusal was announced as
#      "drained" -- the exact condition stage 6b exists to rule out.
#   2. It then required the WHOLE of stdout to be numeric. `as_app` runs a login shell, so Dotenv, RubyLLM and
#      Sidekiq printed informational lines alongside the number; a genuinely empty in-flight set read as
#      unreadable, and REQUIRE_DRAIN stopped a deploy that should have proceeded.
#
# Both were one-line parsing mistakes in a block that only runs on a production host, which is why they were
# found there. These cases run the parser anywhere.
#
# THE LOOP IS EXTRACTED VERBATIM from deploy.sh rather than copied into this file. A copy would drift, and a
# test that passes against a paraphrase of the shipped code proves nothing about the shipped code.
set -Eeuo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY="$HERE/deploy.sh"
[[ -r $DEPLOY ]] || { echo "cannot read $DEPLOY" >&2; exit 1; }

PASS=0
FAIL=0

# From `drained=0` to the first column-0 `done` that follows it: the whole retry loop, unmodified.
extract_loop() {
  awk '/^drained=0$/ { inside = 1 } inside { print } inside && /^done$/ { exit }' "$DEPLOY"
}

LOOP="$(extract_loop)"
[[ -n $LOOP ]] || { echo "could not extract the drain loop from deploy.sh" >&2; exit 1; }
grep -q 'LYNOMIA_BUSY' <<<"$LOOP" || { echo "extracted loop does not mention the sentinel" >&2; exit 1; }

# One case: a stubbed `as_app` returning the given stdout and exit status, the real loop, then the outcome.
#
# `sleep` is stubbed so 30 attempts cost nothing. The ERR trap appends to a FILE rather than setting a
# variable, because `set -E` propagates the trap into subshells where a variable assignment would be lost --
# and "the probe must never abort the deploy" is a property worth testing honestly.
run_case() {
  local status="$1" output="$2"
  local dir; dir="$(mktemp -d)"

  {
    echo 'set -Eeuo pipefail'
    echo 'trap '"'"'echo fired >> "$ERRFILE"'"'"' ERR'
    echo 'sleep() { :; }'
    echo 'as_app() { printf "%s\n" "$PROBE_OUT"; return "$PROBE_STATUS"; }'
    echo "$LOOP"
    echo 'printf "OUTCOME drained=%s busy=%s\n" "$drained" "${busy:-<empty>}"'
  } > "$dir/case.sh"

  : > "$dir/err"
  PROBE_OUT="$output" PROBE_STATUS="$status" ERRFILE="$dir/err" bash "$dir/case.sh" 2>&1
  printf 'ERRTRAP %s\n' "$([[ -s $dir/err ]] && echo fired || echo quiet)"
  rm -rf "$dir"
}

# Every case asserts the whole outcome, not just the number: a case that checked `drained` alone would pass
# while the loop reported a nonsense worker count to the operator.
check() {
  local name="$1" status="$2" output="$3" want_drained="$4" want_busy="$5"
  # `|| true` for the same reason as above: if the loop ever aborts, that is a case to report, not a reason
  # to stop testing.
  local got; got="$(run_case "$status" "$output")" || true
  local outcome; outcome="$(grep '^OUTCOME ' <<<"$got" || true)"
  local errtrap; errtrap="$(grep '^ERRTRAP ' <<<"$got" || true)"
  local want="OUTCOME drained=$want_drained busy=$want_busy"

  if [[ $outcome == "$want" && $errtrap == 'ERRTRAP quiet' ]]; then
    printf '  ok    %s\n' "$name"
    PASS=$((PASS + 1))
  else
    printf '  FAIL  %s\n        want: %s + ERRTRAP quiet\n        got:  %s + %s\n' \
      "$name" "$want" "${outcome:-<no outcome>}" "${errtrap:-<no errtrap>}"
    FAIL=$((FAIL + 1))
  fi
}

NOISE_BEFORE='Dotenv loaded .env
RubyLLM: configuration complete
Sidekiq 7.3.2 connecting to Redis'
NOISE_AFTER='Sidekiq client shutting down'

echo
echo 'Required cases'
check 'A  noisy logs + __LYNOMIA_BUSY__=0 -> drained' \
  0 "$NOISE_BEFORE
__LYNOMIA_BUSY__=0
$NOISE_AFTER" 1 0

check 'B  noisy logs + __LYNOMIA_BUSY__=3 -> 3 busy' \
  0 "$NOISE_BEFORE
__LYNOMIA_BUSY__=3
$NOISE_AFTER" 0 3

check 'C  noisy logs, no sentinel -> unknown, never zero' \
  0 "$NOISE_BEFORE
$NOISE_AFTER" 0 '<empty>'

check 'D  rails runner exits non-zero -> unknown, even with a valid sentinel present' \
  1 "$NOISE_BEFORE
__LYNOMIA_BUSY__=0" 0 '<empty>'

check 'E  malformed sentinel (no value) -> unknown' \
  0 "$NOISE_BEFORE
__LYNOMIA_BUSY__=" 0 '<empty>'

echo
echo 'Adversarial cases: every way an unreadable probe could be mistaken for zero'
check 'F  trailing text on the sentinel line -> unknown, NOT drained' \
  0 "__LYNOMIA_BUSY__=0 and the set is empty" 0 '<empty>'

check 'G  leading text on the sentinel line -> unknown, NOT drained' \
  0 "INFO __LYNOMIA_BUSY__=0" 0 '<empty>'

check 'H  two sentinels disagreeing -> unknown, no winner picked' \
  0 "__LYNOMIA_BUSY__=0
__LYNOMIA_BUSY__=2" 0 '<empty>'

check 'I  two sentinels agreeing -> still unknown, the probe answered twice' \
  0 "__LYNOMIA_BUSY__=0
__LYNOMIA_BUSY__=0" 0 '<empty>'

check 'J  a different key that merely ends in a number -> unknown' \
  0 "$NOISE_BEFORE
workers_size=0" 0 '<empty>'

check 'K  a bare number, which is what the old parser wanted -> unknown' \
  0 "0" 0 '<empty>'

check 'L  negative value -> unknown' \
  0 "__LYNOMIA_BUSY__=-1" 0 '<empty>'

check 'M  non-integer value -> unknown' \
  0 "__LYNOMIA_BUSY__=none" 0 '<empty>'

check 'N  empty output -> unknown' \
  0 "" 0 '<empty>'

check 'O  sentinel-like prefix on a longer key -> unknown' \
  0 "__LYNOMIA_BUSY__X=0" 0 '<empty>'

check 'P  whitespace after the value -> unknown, because the grammar is anchored' \
  0 "__LYNOMIA_BUSY__=0 " 0 '<empty>'

echo
echo 'Integer handling: a digit string must never be read as octal, and must never abort'
check 'Q  leading zeros, non-zero value -> 8 busy, no arithmetic error' \
  0 "__LYNOMIA_BUSY__=08" 0 08

check 'R  all zeros -> drained' \
  0 "__LYNOMIA_BUSY__=00" 1 00

check 'S  large value -> busy' \
  0 "__LYNOMIA_BUSY__=1234" 0 1234

echo
printf '%s passed, %s failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
