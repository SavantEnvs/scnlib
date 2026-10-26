#!/usr/bin/env bash
#
# mayhem/test.sh — RUN scnlib's own GoogleTest suites (built by mayhem/build.sh) plus a known-answer probe.
# The gtest runners are judged by the counts in their own summary line, never by exit status alone,
# and the probe's output is compared to exact expected text.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
cd "$SRC"

emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

passed=0; failed=0; skipped=0

for bin in /mayhem/scn_kat /mayhem/scn_tests /mayhem/scn_impl_tests; do
  if [ ! -x "$bin" ]; then echo "missing $bin — mayhem/build.sh did not produce it" >&2; failed=$((failed+1)); fi
done

# Known-answer probe.
expected='basic 42 3.50 hello
radix 255 5
float 1500.0
class word :
reject 1
overflow 1'
if [ -x /mayhem/scn_kat ]; then
  actual="$(/mayhem/scn_kat 2>&1)"
  if [ "$actual" = "$expected" ]; then passed=$((passed+1)); else
    echo "scn_kat output mismatch:" >&2; diff <(printf '%s\n' "$expected") <(printf '%s\n' "$actual") >&2
    failed=$((failed+1)); fi
fi

# GoogleTest suites: count from the summary lines ("[  PASSED  ] N tests.", "[  FAILED  ] N tests", "[  SKIPPED ] N tests").
for bin in /mayhem/scn_tests /mayhem/scn_impl_tests; do
  [ -x "$bin" ] || continue
  out="$("$bin" 2>&1)"; rc=$?
  p="$(printf '%s\n' "$out" | sed -n 's/^\[  PASSED  \] \([0-9]*\) tests\?\..*/\1/p' | tail -1)"
  f="$(printf '%s\n' "$out" | sed -n 's/^\[  FAILED  \] \([0-9]*\) tests\?, listed below.*/\1/p' | tail -1)"
  s="$(printf '%s\n' "$out" | sed -n 's/^\[  SKIPPED \] \([0-9]*\) tests\?, listed below.*/\1/p' | tail -1)"
  if [ -z "$p" ] || [ "$p" -eq 0 ]; then
    echo "$bin reported no passing tests (rc=$rc)" >&2; printf '%s\n' "$out" | tail -20 >&2
    failed=$((failed+1)); continue
  fi
  passed=$((passed+p)); failed=$((failed+${f:-0})); skipped=$((skipped+${s:-0}))
  [ "$rc" -eq 0 ] || [ "${f:-0}" -gt 0 ] || failed=$((failed+1))
done

emit_ctrf "gtest" "$passed" "$failed" "$skipped"
