#!/bin/sh
# EPS/AI handler: valid renders, pixel cap via bbox, corrupt input,
# missing Ghostscript.
set -u
. "$(dirname -- "$0")/lib.sh"

OUT=$(mktemp) && WORK=$(mktemp -d) && trap 'rm -rf "$OUT" "$WORK"' EXIT

test_valid_eps_renders_data_uri() {
    "$FORGEPEEK" render eps <"$FIXTURES/sample.eps" >"$OUT" 2>/dev/null
    assert_exit0 $? "valid eps exits 0"
    assert_contains "$OUT" "data:image/png;base64," "data URI present"
    assert_not_contains "$OUT" "forgepeek-error" "no error box"
}

test_ai_pdf_renders_data_uri() {
    "$FORGEPEEK" render ai <"$FIXTURES/sample.ai" >"$OUT" 2>/dev/null
    assert_exit0 $? "pdf-compatible .ai exits 0"
    assert_contains "$OUT" "data:image/png;base64," ".ai rendered"
}

test_output_respects_pixel_cap() {
    # 100 pt artwork with a 50 px cap → the decoded PNG must be ≤ 50+1 px.
    FORGEPEEK_MAX_EDGE=50 "$FORGEPEEK" render eps \
        <"$FIXTURES/sample.eps" >"$OUT" 2>/dev/null
    sed -n 's/.*base64,\([^"]*\)".*/\1/p' "$OUT" | base64 -d >"$WORK/cap.png"
    if command -v identify >/dev/null 2>&1; then
        dims=$(identify -format '%w %h' "$WORK/cap.png")
        w=${dims% *}; h=${dims#* }
        if [ "$w" -gt 51 ] || [ "$h" -gt 51 ]; then
            fail "pixel cap not applied (got ${w}x${h}, cap 50)"
        fi
    fi
}

test_oversized_eps_reports_size() {
    FORGEPEEK_MAX_BYTES=16 "$FORGEPEEK" render eps \
        <"$FIXTURES/sample.eps" >"$OUT" 2>/dev/null
    assert_exit0 $? "oversized eps exits 0"
    assert_contains "$OUT" "too large" "size message shown"
}

test_corrupt_eps_error_box() {
    "$FORGEPEEK" render eps <"$FIXTURES/corrupt.eps" >"$OUT" 2>/dev/null
    assert_exit0 $? "corrupt eps exits 0"
    assert_contains "$OUT" "forgepeek-error" "error box emitted"
}

test_missing_gs_reports_dependency() {
    rp=$(make_restricted_path "$WORK/nobin")
    PATH="$rp" "$FORGEPEEK" render eps <"$FIXTURES/sample.eps" >"$OUT" 2>/dev/null
    assert_exit0 $? "missing dep exits 0"
    assert_contains "$OUT" "missing dependency" "names the problem"
    assert_contains "$OUT" "Ghostscript" "names the tool"
}

run_tests
