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
# EVERYTHING UNDER TEST IS EXTRACTED VERBATIM from deploy.sh rather than copied into this file -- the loop, the
# REQUIRE_DRAIN decision that follows it, and the `rails runner` invocation that produces the sentinel. A copy
# would drift, and a test that passes against a paraphrase of the shipped code proves nothing about it.
set -Eeuo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY="$HERE/deploy.sh"
[[ -r $DEPLOY ]] || { echo "cannot read $DEPLOY" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0

ok()   { printf '  ok    %s\n' "$1"; PASS=$((PASS + 1)); }
bad()  { printf '  FAIL  %s\n' "$1"; shift; printf '        %s\n' "$@"; FAIL=$((FAIL + 1)); }

# ---------------------------------------------------------------------------------------------------------
# The three fragments under test.

# The retry loop: `drained=0` to the first column-0 `done`.
LOOP="$(awk '/^drained=0$/ { inside = 1 } inside { print } inside && /^done$/ { exit }' "$DEPLOY")"
# The decision the loop feeds. Extracted too, because "preserve REQUIRE_DRAIN semantics" is a requirement, and
# a requirement nothing executes is a requirement nobody is keeping.
DECISION="$(awk '/^if \[\[ \$drained -eq 0 \]\]; then$/ { inside = 1 } inside { print } inside && /^fi$/ { exit }' "$DEPLOY")"
# The producer. The parser's grammar is only half the contract; a sentinel the Ruby never emits in that exact
# shape is bug 2 again, so the one-liner is run for real further down.
PRODUCER="$(awk '/^  probe_status=0$/ { inside = 1 } inside { print } inside && /\)" \|\| probe_status=\$\?$/ { exit }' "$DEPLOY")"

[[ -n $LOOP     ]] || { echo "could not extract the drain loop from deploy.sh" >&2; exit 1; }
[[ -n $DECISION ]] || { echo "could not extract the REQUIRE_DRAIN decision from deploy.sh" >&2; exit 1; }
[[ -n $PRODUCER ]] || { echo "could not extract the rails runner invocation from deploy.sh" >&2; exit 1; }
grep -q 'LYNOMIA_BUSY' <<<"$LOOP"     || { echo "extracted loop does not mention the sentinel" >&2; exit 1; }
grep -q 'LYNOMIA_BUSY' <<<"$PRODUCER" || { echo "extracted producer does not mention the sentinel" >&2; exit 1; }

# ---------------------------------------------------------------------------------------------------------
# One case against the loop.
#
# The probe's stdout is passed through a FILE, not an environment variable: a realistic noisy probe can exceed
# ARG_MAX, and a harness that cannot express that input cannot test the branch that handles it.
#
# `sleep` is stubbed so 30 attempts cost nothing. The ERR trap appends to a FILE rather than setting a
# variable, because `set -E` propagates the trap into subshells where an assignment would be lost -- and "the
# probe must never abort the deploy" is the property most worth testing honestly. Every call is counted, so a
# case can assert that the loop really did re-probe, and stop.
run_case() {
  local dir="$WORK/run"; rm -rf "$dir"; mkdir -p "$dir"
  printf '%s\n' "$2" > "$dir/attempt_1"           # default: the same output on every attempt
  printf '%s' "$1" > "$dir/status_1"
  shift 2
  local n=2
  while [[ $# -ge 2 ]]; do                        # optional per-attempt overrides: status output status output
    printf '%s' "$1" > "$dir/status_$n"
    printf '%s\n' "$2" > "$dir/attempt_$n"
    shift 2; n=$((n + 1))
  done

  {
    echo 'set -Eeuo pipefail'
    echo 'trap '"'"'echo fired >> "$DIR/err"'"'"' ERR'
    echo 'sleep() { :; }'
    # Faithful in the one way that matters here: output comes from a process, and the status is the process's.
    echo 'as_app() {'
    echo '  local n; n=$(( $(cat "$DIR/calls") + 1 )); echo "$n" > "$DIR/calls"'
    echo '  local f="$DIR/attempt_$n"; [[ -r $f ]] || f="$DIR/attempt_1"'
    echo '  local s="$DIR/status_$n"; [[ -r $s ]] || s="$DIR/status_1"'
    echo '  cat "$f"; return "$(cat "$s")"'
    echo '}'
    echo "$LOOP"
    echo 'printf "OUTCOME drained=%s busy=%s calls=%s\n" "$drained" "${busy:-<empty>}" "$(cat "$DIR/calls")"'
  } > "$dir/case.sh"

  : > "$dir/err"; echo 0 > "$dir/calls"
  DIR="$dir" bash "$dir/case.sh" 2> "$dir/stderr" || true
  printf 'ERRTRAP %s\n' "$([[ -s $dir/err ]] && echo fired || echo quiet)"
  printf 'STDERR %s\n' "$([[ -s $dir/stderr ]] && echo noisy || echo clean)"
}

# Asserts the whole outcome, not just the number: a case that checked `drained` alone would pass while the
# loop reported a nonsense worker count to the operator. stderr is asserted clean because a bash diagnostic
# (an arithmetic error, say) is a defect that would otherwise be graded 'ok'.
# Compares the whole outcome, not just the number: a case that checked `drained` alone would pass while the
# loop reported a nonsense worker count to the operator. stderr must be clean, because a bash diagnostic -- an
# arithmetic error, say -- is a defect that would otherwise be graded 'ok'. `want_calls` empty means the probe
# count is not part of this case.
grade() {
  local name="$1" want="$2" got="$3"
  local outcome errtrap stderr
  outcome="$(grep '^OUTCOME ' <<<"$got" || true)"
  errtrap="$(grep '^ERRTRAP ' <<<"$got" || true)"
  stderr="$(grep '^STDERR ' <<<"$got" || true)"

  if [[ $outcome == "$want" && $errtrap == 'ERRTRAP quiet' && $stderr == 'STDERR clean' ]]; then
    ok "$name"
  else
    bad "$name" "want: $want + ERRTRAP quiet + STDERR clean" "got:  ${outcome:-<none>} + ${errtrap:-?} + ${stderr:-?}"
  fi
}

# The same output on every attempt. The probe count is whatever the loop does.
check() {
  local name="$1" status="$2" output="$3" want_drained="$4" want_busy="$5"
  local got; got="$(run_case "$status" "$output")" || true
  local calls; calls="$(sed -n 's/.*calls=\([0-9]*\).*/\1/p' <<<"$got" | head -1)"
  grade "$name" "OUTCOME drained=$want_drained busy=$want_busy calls=${calls:-?}" "$got"
}

# A different answer per attempt, and an exact probe count: the only way to show the loop re-probes and stops.
check_seq() {
  local name="$1" want_drained="$2" want_busy="$3" want_calls="$4"; shift 4
  local got; got="$(run_case "$@")" || true
  grade "$name" "OUTCOME drained=$want_drained busy=$want_busy calls=$want_calls" "$got"
}

NOISE_BEFORE='Dotenv loaded .env
RubyLLM: configuration complete
Sidekiq 7.3.2 connecting to Redis'
NOISE_AFTER='Sidekiq client shutting down'

echo
echo 'Required cases'
check 'A  noisy logs + __LYNOMIA_BUSY__=0 -> drained' 0 "$NOISE_BEFORE
__LYNOMIA_BUSY__=0
$NOISE_AFTER" 1 0
check 'B  noisy logs + __LYNOMIA_BUSY__=3 -> 3 busy' 0 "$NOISE_BEFORE
__LYNOMIA_BUSY__=3
$NOISE_AFTER" 0 3
check 'C  noisy logs, no sentinel -> unknown, never zero' 0 "$NOISE_BEFORE
$NOISE_AFTER" 0 '<empty>'
check 'D  runner exits non-zero -> unknown, even with a valid sentinel present' 1 "$NOISE_BEFORE
__LYNOMIA_BUSY__=0" 0 '<empty>'
check 'E  malformed sentinel (no value) -> unknown' 0 "$NOISE_BEFORE
__LYNOMIA_BUSY__=" 0 '<empty>'

echo
echo 'Adversarial cases: every way an unreadable probe could be mistaken for zero'
check 'F  trailing text on the sentinel line -> unknown' 0 "__LYNOMIA_BUSY__=0 and the set is empty" 0 '<empty>'
check 'G  leading text on the sentinel line -> unknown' 0 "INFO __LYNOMIA_BUSY__=0" 0 '<empty>'
check 'H  two sentinels disagreeing -> unknown, no winner picked' 0 "__LYNOMIA_BUSY__=0
__LYNOMIA_BUSY__=2" 0 '<empty>'
check 'I  two sentinels agreeing -> still unknown, the probe answered twice' 0 "__LYNOMIA_BUSY__=0
__LYNOMIA_BUSY__=0" 0 '<empty>'
check 'J  a different key that merely ends in a number -> unknown' 0 "workers_size=0" 0 '<empty>'
check 'K  a bare number, which is what the old parser wanted -> unknown' 0 "0" 0 '<empty>'
check 'L  negative value -> unknown' 0 "__LYNOMIA_BUSY__=-1" 0 '<empty>'
check 'M  non-integer value -> unknown' 0 "__LYNOMIA_BUSY__=none" 0 '<empty>'
check 'N  empty output -> unknown' 0 "" 0 '<empty>'
check 'O  sentinel-like prefix on a longer key -> unknown' 0 "__LYNOMIA_BUSY__X=0" 0 '<empty>'
check 'P  whitespace after the value -> unknown, the grammar is anchored' 0 "__LYNOMIA_BUSY__=0 " 0 '<empty>'

echo
echo 'Integer handling: a digit string must never be read as octal, and must never abort'
check 'Q  leading zeros, non-zero -> 8 busy, no arithmetic error on stderr' 0 "__LYNOMIA_BUSY__=08" 0 08
check 'R  all zeros -> drained' 0 "__LYNOMIA_BUSY__=00" 1 00
check 'S  large value -> busy' 0 "__LYNOMIA_BUSY__=1234" 0 1234

echo
echo 'The loop must really loop, and really stop'
# The shape a retry loop exists for, and the one a fixed-output case cannot show: the count falling to zero
# while the loop runs. Attempts 1-2 are busy, attempt 3 is drained, so the loop must probe exactly 3 times.
check_seq 'T  busy, busy, then drained -> drained on the third probe' 1 0 3 \
  0 '__LYNOMIA_BUSY__=2' 0 '__LYNOMIA_BUSY__=1' 0 '__LYNOMIA_BUSY__=0'
# An unreadable probe must exhaust the budget rather than give up early or spin forever.
check_seq 'U  never readable -> exactly 30 probes, then unknown' 0 '<empty>' 30 0 'no sentinel here'

echo
echo 'The last-attempt diagnostic must not abort the deploy'
# The regression an adversarial review found in this very file: `printf ... | head -n 20 | sed ...` takes
# SIGPIPE once the probe's output exceeds the 64 KiB pipe buffer, and under `pipefail` + the ERR trap that
# aborts the deploy -- from the one branch whose whole purpose is to not abort.
BIG=''
for _ in $(seq 1 3000); do BIG+='Dotenv loaded a long informational line that exceeds the pipe buffer'$'\n'; done
check 'V  240KB of sentinel-free output -> unknown, and the deploy survives' 0 "$BIG" 0 '<empty>'

# ---------------------------------------------------------------------------------------------------------
echo
echo 'The REQUIRE_DRAIN decision the loop feeds'
decide() {
  local drained="$1" require="$2"
  local dir="$WORK/decide"; rm -rf "$dir"; mkdir -p "$dir"
  {
    echo 'set -Eeuo pipefail'
    echo 'fail() { printf "FAILED: %s\n" "$*"; exit 1; }'
    echo "drained=$drained"
    echo "$DECISION"
    echo 'echo PROCEEDED'
  } > "$dir/d.sh"
  if [[ -n $require ]]; then REQUIRE_DRAIN=1 bash "$dir/d.sh" 2>&1 || true
  else bash "$dir/d.sh" 2>&1 || true; fi
}
got="$(decide 1 '')";  [[ $got == 'PROCEEDED' ]] && ok 'W  drained, REQUIRE_DRAIN unset -> proceeds silently' || bad 'W' "got: $got"
got="$(decide 1 '1')"; [[ $got == 'PROCEEDED' ]] && ok 'X  drained, REQUIRE_DRAIN set   -> proceeds silently' || bad 'X' "got: $got"
got="$(decide 0 '')";  grep -q '^WARNING:' <<<"$got" && grep -q 'PROCEEDED' <<<"$got" \
  && ok 'Y  not drained, REQUIRE_DRAIN unset -> warns and proceeds' || bad 'Y' "got: $got"
got="$(decide 0 '1')"; grep -q '^FAILED:' <<<"$got" && ! grep -q 'PROCEEDED' <<<"$got" \
  && ok 'Z  not drained, REQUIRE_DRAIN set   -> stops the deploy' || bad 'Z' "got: $got"

# ---------------------------------------------------------------------------------------------------------
echo
echo 'The producer: the Ruby must emit a line the parser above actually accepts'
if ! command -v ruby > /dev/null; then
  echo '  SKIP  no ruby on this host, so the sentinel producer cannot be run here'
else
  mkdir -p "$WORK/bin" "$WORK/lib/sidekiq"
  cat > "$WORK/lib/sidekiq/api.rb" <<'STUB'
module Sidekiq
  class Stats
    def workers_size = Integer(ENV.fetch('FAKE_WORKERS', '0'))
  end
end
STUB
  # Stands in for `bundle exec rails runner`, and prints the login-shell noise that broke the last parser.
  cat > "$WORK/bin/rails" <<'FAKE'
#!/usr/bin/env bash
echo 'Dotenv loaded .env'
echo 'RubyLLM: configuration complete'
[[ $1 == runner ]] || { echo "unexpected rails invocation: $*" >&2; exit 2; }
shift
ruby -e "$1"
rc=$?
echo 'Sidekiq client shutting down'
exit $rc
FAKE
  chmod +x "$WORK/bin/rails"
  cat > "$WORK/bin/bundle" <<'FAKE'
#!/usr/bin/env bash
[[ $1 == exec ]] && shift
exec "$@"
FAKE
  chmod +x "$WORK/bin/bundle"

  produce() {
    local dir="$WORK/prod"; rm -rf "$dir"; mkdir -p "$dir"
    {
      echo 'set -Eeuo pipefail'
      # The real as_app, minus sudo: the same `bash -lc "cd '<dir>' && $1"` interpolation, which is what
      # decides whether the %q(), the %() and the #{} in the one-liner survive to Ruby intact.
      #
      # PATH is re-prepended INSIDE the login shell. `-l` re-runs the profile, which puts the real rbenv
      # shims back in front -- so without this the stubs below are shadowed by the host's actual bundler,
      # and the case measures the host's Ruby setup instead of the one-liner's quoting.
      printf 'as_app() { bash -lc "export PATH=%s:\\$PATH; cd %s && $1"; }\n' \
        "'$WORK/bin'" "'$HERE'"
      echo "$PRODUCER"
      echo 'printf "STATUS %s\n" "$probe_status"'
      echo 'printf "%s\n" "$probe_out"'
    } > "$dir/p.sh"
    PATH="$WORK/bin:$PATH" RUBYLIB="$WORK/lib" FAKE_WORKERS="$1" bash "$dir/p.sh" 2>&1 || true
  }

  for want in 0 4 17; do
    out="$(produce "$want")"
    # Exactly what the loop's own sed looks for, applied to what the Ruby actually printed.
    extracted="$(sed -n 's/^__LYNOMIA_BUSY__=\([0-9][0-9]*\)$/\1/p' <<<"$out")"
    if [[ $extracted == "$want" && $(grep -c . <<<"$extracted") -eq 1 ]]; then
      ok "producer emits one parseable sentinel for workers_size=$want"
    else
      bad "producer for workers_size=$want" "extracted: '${extracted:-<none>}'" "raw: $(tr '\n' '|' <<<"$out")"
    fi
  done
fi

echo
printf '%s passed, %s failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
