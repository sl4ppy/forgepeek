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

test_postmessage_repair_recovers_corrupt_embed() {
    # Forgejo's standalone render route corrupts binary input (UTF-8
    # conversion). The footer shim posts pristine /raw/ bytes into the
    # viewer, which must recover. Simulate: render a page whose embedded
    # model is mangled, then post the real bytes via postMessage (in a
    # top-level page window.parent === window, so the source check passes).
    python3 - "$FIXTURES/cube-binary.stl" "$WORK/mangled.stl" <<'EOF'
import sys
data = open(sys.argv[1], 'rb').read()
# what ToUTF8WithFallbackReader does to binary: invalid sequences -> U+FFFD
open(sys.argv[2], 'wb').write(data.decode('latin-1').encode('utf-8'))
EOF
    "$FORGEPEEK" render stl <"$WORK/mangled.stl" >"$WORK/page.html" 2>/dev/null
    b64=$(base64 <"$FIXTURES/cube-binary.stl" | tr -d '\n')
    cat >>"$WORK/page.html" <<EOF
<script>
var bin = atob("$b64");
var bytes = new Uint8Array(bin.length);
for (var i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
window.postMessage({forgepeekRaw: bytes.buffer}, '*');
</script>
EOF
    "$BROWSER" --headless=new --disable-gpu --no-sandbox \
        --use-gl=swiftshader --enable-unsafe-swiftshader \
        --virtual-time-budget=5000 --dump-dom "$WORK/page.html" >"$OUT" 2>/dev/null
    assert_contains "$OUT" "12 triangles" "viewer recovered via posted pristine bytes"
}

test_footer_shim_adds_zoom_controls_to_image_previews() {
    # The contrib footer shim enhances sanitized-mode image previews with
    # zoom/pan. Compose a page from real psd handler output plus the shim
    # script (as Forgejo would inject it), fire a wheel event, and check
    # the controls exist and the transform applied.
    {
        printf '<div class="file-view markup forgepeek_psd">\n'
        "$FORGEPEEK" render psd <"$FIXTURES/sample-2layer.psd" 2>/dev/null
        printf '</div>\n'
        sed -n '/<script>/,/<\/script>/p' "$ROOT/contrib/forgejo-iframe-fix/footer.tmpl"
        cat <<'EOF'
<script>
window.addEventListener('load', function () {
  var box = document.querySelector('.forgepeek-image');
  box.dispatchEvent(new WheelEvent('wheel', {deltaY: -120, clientX: 10, clientY: 10, bubbles: true, cancelable: true}));
});
</script>
EOF
    } >"$WORK/zoom.html"
    "$BROWSER" --headless=new --disable-gpu --no-sandbox \
        --virtual-time-budget=5000 --dump-dom "$WORK/zoom.html" >"$OUT" 2>/dev/null
    assert_contains "$OUT" 'data-fp-zoom' "zoom enhancement attached"
    assert_contains "$OUT" 'title="Zoom in"' "zoom-in button present"
    assert_contains "$OUT" 'scale(1.2)' "wheel event zoomed the image"
    assert_contains "$OUT" '>120%<' "zoom label updated"
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
