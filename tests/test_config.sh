#!/bin/sh
# Config generator: one stanza per extension, iframe vs sanitized emission,
# path override, filtering, ini and env output formats.
set -u
. "$(dirname -- "$0")/lib.sh"

OUT=$(mktemp) && trap 'rm -f "$OUT" "$OUT.stl"' EXIT

test_stanza_per_extension() {
    "$FORGEPEEK" config >"$OUT" 2>&1
    assert_exit0 $? "config succeeds"
    for s in forgepeek_psd forgepeek_psb forgepeek_eps forgepeek_ai \
             forgepeek_stl forgepeek_fbx; do
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
    assert_contains "$OUT" "\[markup.sanitizer.forgepeek_psd.data_uri\]" "psd data-uri rule"
    assert_contains "$OUT" "ALLOW_DATA_URI_IMAGES = true" "data uri images enabled"
    assert_contains "$OUT" "\[markup.sanitizer.forgepeek_eps.img_style\]" "eps img style rule"
}

test_iframe_handlers_get_no_sanitizer_rules() {
    "$FORGEPEEK" config >"$OUT" 2>&1
    grep -A6 '\[markup.forgepeek_stl\]' "$OUT" >"$OUT.stl"
    assert_contains "$OUT.stl" "RENDER_CONTENT_MODE = iframe" "stl is iframe mode"
    assert_not_contains "$OUT" "sanitizer.forgepeek_stl" "no sanitizer rules for stl"
    assert_not_contains "$OUT" "sanitizer.forgepeek_fbx" "no sanitizer rules for fbx"
}

test_path_override() {
    "$FORGEPEEK" config --path /data/forgepeek >"$OUT" 2>&1
    assert_contains "$OUT" 'RENDER_COMMAND = "/data/forgepeek/forgepeek render psd"' \
        "--path overrides the command prefix"
}

test_handler_filter() {
    "$FORGEPEEK" config psd >"$OUT" 2>&1
    assert_contains "$OUT" "\[markup.forgepeek_psd\]" "filtered handler present"
    assert_not_contains "$OUT" "\[markup.forgepeek_stl\]" "other handlers omitted"
}

test_ini_values_have_no_inline_comment_hazard() {
    # go-ini starts an inline comment at " #" or " ;" — a regexp containing
    # either would be silently truncated by Forgejo's parser.
    "$FORGEPEEK" config >"$OUT" 2>&1
    if grep -n 'REGEXP.*\( #\| ;\)' "$OUT"; then
        fail "REGEXP value contains ' #' or ' ;' (ini inline-comment hazard)"
    fi
}

test_env_format_sections_and_escaping() {
    "$FORGEPEEK" config --format env --path /usr/local/lib/forgepeek >"$OUT" 2>&1
    assert_exit0 $? "env format succeeds"
    assert_contains "$OUT" "FORGEJO__MARKUP_0X2E_FORGEPEEK_PSD__ENABLED=true" \
        "dot escaped as _0X2E_ in section name"
    assert_contains "$OUT" \
        "FORGEJO__MARKUP_0X2E_FORGEPEEK_PSD__RENDER_COMMAND=/usr/local/lib/forgepeek/forgepeek render psd" \
        "command value unquoted in env format"
    assert_contains "$OUT" \
        "FORGEJO__MARKUP_0X2E_SANITIZER_0X2E_FORGEPEEK_PSD_0X2E_DATA_URI__ALLOW_DATA_URI_IMAGES=true" \
        "multi-dot sanitizer section escaped"
    if grep -q '^\[markup' "$OUT"; then
        fail "ini stanza lines leaked into env format"
    fi
}

test_env_format_dollar_doubled_for_compose() {
    # compose interpolates single '$' in environment: values; regex anchors
    # must arrive as '$$'.
    "$FORGEPEEK" config --format env >"$OUT" 2>&1
    if grep 'REGEXP=' "$OUT" | grep -v '\$\$' | grep -q '\$'; then
        fail "regexp '\$' not doubled for compose interpolation"
    fi
    assert_contains "$OUT" 'REGEXP=^forgepeek\[a-z -\]\*\$\$' "class regexp anchored with \$\$"
}

test_env_format_names_are_portable() {
    # environment-to-ini portable set is A-Z0-9_ — no dashes or dots may
    # leak into variable names.
    "$FORGEPEEK" config --format env >"$OUT" 2>&1
    if sed -n "s/.*'\(FORGEJO__[^=]*\)=.*/\1/p" "$OUT" | grep -q '[^A-Z0-9_]'; then
        fail "env variable name contains characters outside A-Z0-9_"
    fi
}

run_tests
