#!/bin/sh
# Config generator: one stanza per extension, iframe vs sanitized emission,
# path override, filtering.
set -u
. "$(dirname -- "$0")/lib.sh"

OUT=$(mktemp) && trap 'rm -f "$OUT"' EXIT

test_stanza_per_extension() {
    "$FORGEPEEK" config >"$OUT" 2>&1
    assert_exit0 $? "config succeeds"
    for s in forgepeek-psd forgepeek-psb forgepeek-eps forgepeek-ai \
             forgepeek-stl forgepeek-fbx; do
        assert_contains "$OUT" "\[markup.$s\]" "stanza for $s"
    done
    assert_contains "$OUT" "RENDER_COMMAND = \"$ROOT/forgepeek render psb\"" \
        "psb command carries its own extension"
}

test_common_keys() {
    "$FORGEPEEK" config >"$OUT" 2>&1
    assert_contains "$OUT" "NEED_POSTPROCESS = false" "postprocess disabled"
    assert_contains "$OUT" "IS_INPUT_FILE = false" "stdin mode"
    assert_not_contains "$OUT" "RENDER_CONTENT_MODE = no-sanitizer" "never no-sanitizer"
}

test_sanitized_handlers_get_sanitizer_rules() {
    "$FORGEPEEK" config >"$OUT" 2>&1
    assert_contains "$OUT" "\[markup.sanitizer.forgepeek-psd.data-uri\]" "psd data-uri rule"
    assert_contains "$OUT" "ALLOW_DATA_URI_IMAGES = true" "data uri images enabled"
    assert_contains "$OUT" "\[markup.sanitizer.forgepeek-eps.img-style\]" "eps img style rule"
}

test_iframe_handlers_get_no_sanitizer_rules() {
    "$FORGEPEEK" config >"$OUT" 2>&1
    grep -A6 '\[markup.forgepeek-stl\]' "$OUT" >"$OUT.stl"
    assert_contains "$OUT.stl" "RENDER_CONTENT_MODE = iframe" "stl is iframe mode"
    assert_not_contains "$OUT" "sanitizer.forgepeek-stl" "no sanitizer rules for stl"
    assert_not_contains "$OUT" "sanitizer.forgepeek-fbx" "no sanitizer rules for fbx"
    rm -f "$OUT.stl"
}

test_path_override() {
    "$FORGEPEEK" config --path /data/forgepeek >"$OUT" 2>&1
    assert_contains "$OUT" 'RENDER_COMMAND = "/data/forgepeek/forgepeek render psd"' \
        "--path overrides the command prefix"
}

test_handler_filter() {
    "$FORGEPEEK" config psd >"$OUT" 2>&1
    assert_contains "$OUT" "\[markup.forgepeek-psd\]" "filtered handler present"
    assert_not_contains "$OUT" "\[markup.forgepeek-stl\]" "other handlers omitted"
}

test_ini_values_have_no_inline_comment_hazard() {
    # go-ini starts an inline comment at " #" or " ;" — a regexp containing
    # either would be silently truncated by Forgejo's parser.
    "$FORGEPEEK" config >"$OUT" 2>&1
    if grep -n 'REGEXP.*\( #\| ;\)' "$OUT"; then
        fail "REGEXP value contains ' #' or ' ;' (ini inline-comment hazard)"
    fi
}

run_tests
