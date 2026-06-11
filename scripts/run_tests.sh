#!/usr/bin/env bash
# Runs flutter test with the `failures-only` reporter so the output stays small
# and immediately readable:
#   - all pass -> a single line:  "+N: All tests passed!"
#   - failures -> for each failing test only: its name, expected/actual, and the
#                 test file:line + stack. Passing tests produce no noise.
#
# Full machine-readable detail for every test is also written to a JSON file as
# an escape hatch (query it with jq instead of reading the whole thing).
#
# Usage: ./scripts/run_tests.sh [flutter test args]
#   ./scripts/run_tests.sh                                  # whole suite
#   ./scripts/run_tests.sh test/providers/foo_test.dart     # one file

TXT=/tmp/flutter_test_result.txt    # human-readable failures-only output
JSON=/tmp/flutter_test_result.json  # full machine-readable detail

flutter test --reporter failures-only --file-reporter "json:$JSON" "$@" > "$TXT" 2>&1
EXIT=$?

# The failures-only output is tiny on success and contains exactly the failing
# tests (with reasons) on failure, so print it straight to stdout. Only cap it
# in the rare case that a huge number of tests fail at once.
if [ "$(wc -l < "$TXT")" -le 200 ]; then
  cat "$TXT"
else
  echo "=== failing tests ($(grep -cE '\[E\]$' "$TXT")) — names only, output truncated ==="
  grep -E '\[E\]$' "$TXT"
  echo
  tail -n 1 "$TXT"   # the "+N -M: Some tests failed." summary line
  echo "(full reasons in $TXT)"
fi

# Escape hatch for deep dives. List failing test names without reading the file:
#   jq -r 'select(.type=="testDone" and .result!="success").testID as $i
#          | $i' "$JSON"   # then map $i via testStart events
echo
echo "Full output: $TXT   |   JSON detail: $JSON"
exit $EXIT
