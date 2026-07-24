#!/bin/sh
# Dispatcher behavior: extension routing, unknown extensions, misconfiguration.
set -u
. "$(dirname -- "$0")/lib.sh"

OUT=$(mktemp) && trap 'rm -f "$OUT"' EXIT

test_version_prints() {
    "$FORGEPEEK" version >"$OUT" 2>&1
    assert_exit0 $? "version should succeed"
    assert_contains "$OUT" "forgepeek" "version output"
}

test_list_shows_handlers() {
    "$FORGEPEEK" list >"$OUT" 2>&1
    assert_exit0 $? "list should succeed"
    assert_contains "$OUT" "psd" "psd handler listed"
    assert_contains "$OUT" ".psd,.psb" "psd extensions listed"
}

test_render_without_ext_emits_error_html() {
    printf x | "$FORGEPEEK" render >"$OUT" 2>/dev/null
    assert_exit0 $? "render with no ext must exit 0"
    assert_contains "$OUT" "forgepeek-error" "error box emitted"
}

test_render_unknown_ext_emits_error_html() {
    printf x | "$FORGEPEEK" render xyz >"$OUT" 2>/dev/null
    assert_exit0 $? "render of unknown ext must exit 0"
    assert_contains "$OUT" "no handler" "explains no handler claims it"
}

test_render_routes_psb_to_psd_handler() {
    "$FORGEPEEK" render PSB <"$FIXTURES/sample.psb" >"$OUT" 2>/dev/null
    assert_exit0 $? "uppercase ext must route (case-insensitive)"
    assert_contains "$OUT" "data:image/png;base64," "psb routed to psd handler"
}

test_unknown_command_exits_nonzero() {
    if "$FORGEPEEK" frobnicate >"$OUT" 2>&1; then
        fail "unknown command should exit non-zero"
    fi
}

run_tests
