#!/bin/sh
# STL/FBX handlers: self-contained iframe page structure, embedded model
# integrity, size cap via client-rendered notice, explicit height guard.
set -u
. "$(dirname -- "$0")/lib.sh"

OUT=$(mktemp) && WORK=$(mktemp -d) && trap 'rm -rf "$OUT" "$WORK"' EXIT

# extract_model OUTFILE — decode the base64 payload embedded in the page
extract_model() {
    sed -n 's/.*ForgePeekViewer.init({format:"[a-z]*",data:"\([A-Za-z0-9+/=]*\)".*/\1/p' \
        "$OUT" | base64 -d
}

page_asserts() { # page_asserts FORMAT
    assert_contains "$OUT" "<!DOCTYPE html>" "complete HTML document"
    assert_contains "$OUT" "ForgePeekViewer" "viewer bundle inlined"
    assert_contains "$OUT" "format:\"$1\"" "init called for $1"
    assert_contains "$OUT" "min-height: 480px" "explicit viewer height (iframe zero-height guard)"
    # Self-contained: nothing loaded from the network at view time. (The
    # bundle itself contains harmless namespace URL strings, so check for
    # loading attributes, not bare "http".)
    assert_not_contains "$OUT" 'src="http' "no external scripts/images"
    assert_not_contains "$OUT" 'href="http' "no external stylesheets"
    assert_not_contains "$OUT" "importScripts" "no worker imports"
}

test_stl_binary_page() {
    "$FORGEPEEK" render stl <"$FIXTURES/cube-binary.stl" >"$OUT" 2>/dev/null
    assert_exit0 $? "binary stl exits 0"
    page_asserts stl
    extract_model >"$WORK/roundtrip.stl"
    if ! cmp -s "$WORK/roundtrip.stl" "$FIXTURES/cube-binary.stl"; then
        fail "embedded base64 does not round-trip to the original bytes"
    fi
}

test_stl_ascii_page() {
    "$FORGEPEEK" render stl <"$FIXTURES/tetra-ascii.stl" >"$OUT" 2>/dev/null
    assert_exit0 $? "ascii stl exits 0"
    page_asserts stl
}

test_fbx_page() {
    "$FORGEPEEK" render fbx <"$FIXTURES/cube-ascii.fbx" >"$OUT" 2>/dev/null
    assert_exit0 $? "fbx exits 0"
    page_asserts fbx
    extract_model >"$WORK/roundtrip.fbx"
    if ! cmp -s "$WORK/roundtrip.fbx" "$FIXTURES/cube-ascii.fbx"; then
        fail "embedded base64 does not round-trip to the original bytes"
    fi
}

test_3d_size_cap_uses_own_limit() {
    # Below the 3D cap but above the 2D cap: must still render (3D uses
    # FORGEPEEK_MAX_BYTES_3D, not FORGEPEEK_MAX_BYTES).
    FORGEPEEK_MAX_BYTES=100 "$FORGEPEEK" render stl \
        <"$FIXTURES/cube-binary.stl" >"$OUT" 2>/dev/null
    assert_contains "$OUT" 'init({format:"stl",data:"' "2D cap does not apply to 3D handlers"
}

test_3d_too_large_notice_is_client_side() {
    FORGEPEEK_MAX_BYTES_3D=100 "$FORGEPEEK" render stl \
        <"$FIXTURES/cube-binary.stl" >"$OUT" 2>/dev/null
    assert_exit0 $? "oversized stl exits 0"
    assert_contains "$OUT" "tooLarge" "client-side too-large notice"
    assert_contains "$OUT" "ForgePeekViewer" "page still self-contained"
    assert_not_contains "$OUT" 'init({format:"stl",data:"' "model bytes not embedded"
}

test_corrupt_stl_still_emits_page() {
    # Parse errors surface client-side; the server must still emit a page.
    "$FORGEPEEK" render stl <"$FIXTURES/corrupt.stl" >"$OUT" 2>/dev/null
    assert_exit0 $? "corrupt stl exits 0"
    assert_contains "$OUT" "<!DOCTYPE html>" "page emitted for client-side error"
}

run_tests
