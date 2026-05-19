#!/usr/bin/env bash
# Runs flutter test and writes output to /tmp/flutter_test_result.txt
# Usage: ./scripts/run_tests.sh [optional flutter test args]
# Output file has full output; last lines contain pass/fail summary.

OUTPUT=/tmp/flutter_test_result.txt

flutter test "$@" > "$OUTPUT" 2>&1
EXIT=$?

# Print summary line(s) only to stdout
grep -E "All tests passed|Some tests failed|\+[0-9]+ -[0-9]+:" "$OUTPUT" | tail -3
echo "Full output: $OUTPUT"
exit $EXIT
