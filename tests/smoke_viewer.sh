#!/bin/sh
# Headless-browser smoke test for the 3D viewer pages: render each 3D
# fixture through the real handler, load the resulting HTML in headless
# Chrome/Chromium, and assert the WebGL canvas plus the triangle-count HUD
# appear (catching bundle/loader breakage the shell tests can't see).
#
# Skips with exit 0 when no Chrome/Chromium is installed — in that case run
# the checks in tests/integration-manual.md instead.
set -u
. "$(dirname -- "$0")/lib.sh"

BROWSER=''
for c in chromium chromium-browser google-chrome google-chrome-stable; do
    if command -v "$c" >/dev/null 2>&1; then BROWSER=$c; break; fi
done
if [ -z "$BROWSER" ]; then
    echo "SKIP smoke_viewer: no Chrome/Chromium found (see tests/integration-manual.md)"
    exit 0
fi

WORK=$(mktemp -d) && trap 'rm -rf "$WORK"' EXIT

# dump_dom FIXTURE FORMAT — render handler output and let the browser run it.
# --virtual-time-budget waits for async work (requestAnimationFrame etc).
dump_dom() {
    "$FORGEPEEK" render "$2" <"$FIXTURES/$1" >"$WORK/page.html" 2>/dev/null
    "$BROWSER" --headless=new --disable-gpu --no-sandbox --hide-scrollbars \
        --use-gl=swiftshader --enable-unsafe-swiftshader \
        --virtual-time-budget=5000 --dump-dom "$WORK/page.html" 2>"$WORK/browser.log"
}

test_stl_binary_viewer_boots() {
    dump_dom cube-binary.stl stl >"$OUT"
    assert_contains "$OUT" "<canvas" "WebGL canvas initialized"
    assert_contains "$OUT" "12 triangles" "triangle HUD for binary cube"
}

test_stl_ascii_viewer_boots() {
    dump_dom tetra-ascii.stl stl >"$OUT"
    assert_contains "$OUT" "<canvas" "WebGL canvas initialized"
    assert_contains "$OUT" "4 triangles" "triangle HUD for ascii tetra"
}

test_fbx_viewer_boots() {
    dump_dom cube-ascii.fbx fbx >"$OUT"
    assert_contains "$OUT" "<canvas" "WebGL canvas initialized"
    assert_contains "$OUT" "12 triangles" "triangle HUD for fbx cube"
}

test_corrupt_stl_shows_client_error() {
    dump_dom corrupt.stl stl >"$OUT"
    assert_contains "$OUT" "fp-error" "client-side parse error box"
    assert_contains "$OUT" "could not display" "friendly error text"
}

test_too_large_shows_client_notice() {
    "$FORGEPEEK" render stl <"$FIXTURES/cube-binary.stl" >"$WORK/big.html" 2>/dev/null
    FORGEPEEK_MAX_BYTES_3D=100 "$FORGEPEEK" render stl \
        <"$FIXTURES/cube-binary.stl" >"$WORK/page.html" 2>/dev/null
    "$BROWSER" --headless=new --disable-gpu --no-sandbox \
        --virtual-time-budget=5000 --dump-dom "$WORK/page.html" >"$OUT" 2>/dev/null
    assert_contains "$OUT" "fp-notice" "client-side notice box"
    assert_contains "$OUT" "too large" "size message"
}

OUT=$WORK/dom.html
run_tests
