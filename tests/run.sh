#!/bin/sh
# forgepeek test runner: executes every tests/test_*.sh with dash if
# available (strictest common shell), plain sh otherwise.
set -u
cd "$(dirname -- "$0")" || exit 1

SHELL_BIN=sh
command -v dash >/dev/null 2>&1 && SHELL_BIN=dash

overall=0
for t in test_*.sh; do
    [ -f "$t" ] || continue
    "$SHELL_BIN" "$t" || overall=1
done

if [ "$overall" -eq 0 ]; then
    echo "ALL TESTS PASSED"
else
    echo "TESTS FAILED" >&2
fi
exit "$overall"
