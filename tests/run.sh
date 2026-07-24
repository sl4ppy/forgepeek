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

# Loader-level checks against the pinned three.js (needs viewer/node_modules;
# run 'sh viewer/build.sh' once to populate it).
if command -v node >/dev/null 2>&1 && [ -d ../viewer/node_modules ]; then
    node parse_check.mjs || overall=1
else
    echo "SKIP parse_check: node or viewer/node_modules unavailable"
fi

# Headless-browser smoke test (self-skips without Chrome/Chromium).
"$SHELL_BIN" smoke_viewer.sh || overall=1

if [ "$overall" -eq 0 ]; then
    echo "ALL TESTS PASSED"
else
    echo "TESTS FAILED" >&2
fi
exit "$overall"
