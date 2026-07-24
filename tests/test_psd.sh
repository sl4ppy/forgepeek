#!/bin/sh
# PSD handler: valid render, CMYK conversion, size cap, corrupt input,
# missing dependency, composite→flatten fallback.
set -u
. "$(dirname -- "$0")/lib.sh"

OUT=$(mktemp) && WORK=$(mktemp -d) && trap 'rm -rf "$OUT" "$WORK"' EXIT

test_valid_psd_renders_data_uri() {
    "$FORGEPEEK" render psd <"$FIXTURES/sample-2layer.psd" >"$OUT" 2>/dev/null
    assert_exit0 $? "valid psd exits 0"
    assert_contains "$OUT" "data:image/png;base64," "data URI present"
    assert_contains "$OUT" "max-width:100%" "responsive img styling"
    assert_not_contains "$OUT" "forgepeek-error" "no error box"
}

test_cmyk_psd_renders() {
    "$FORGEPEEK" render psd <"$FIXTURES/sample-cmyk.psd" >"$OUT" 2>/dev/null
    assert_exit0 $? "cmyk psd exits 0"
    assert_contains "$OUT" "data:image/png;base64," "cmyk converted to sRGB png"
}

test_oversized_psd_reports_size() {
    FORGEPEEK_MAX_BYTES=1024 "$FORGEPEEK" render psd \
        <"$FIXTURES/sample-2layer.psd" >"$OUT" 2>/dev/null
    assert_exit0 $? "oversized psd exits 0"
    assert_contains "$OUT" "too large" "size message shown"
    assert_not_contains "$OUT" "data:image" "no conversion attempted"
}

test_corrupt_psd_error_box() {
    "$FORGEPEEK" render psd <"$FIXTURES/corrupt.psd" >"$OUT" 2>/dev/null
    assert_exit0 $? "corrupt psd exits 0"
    assert_contains "$OUT" "forgepeek-error" "error box emitted"
    assert_contains "$OUT" "<details" "stderr details element present"
}

test_empty_input_error_box() {
    : | "$FORGEPEEK" render psd >"$OUT" 2>/dev/null
    assert_exit0 $? "empty input exits 0"
    assert_contains "$OUT" "empty file" "empty-file message"
}

test_missing_imagemagick_reports_dependency() {
    rp=$(make_restricted_path "$WORK/nobin")
    PATH="$rp" "$FORGEPEEK" render psd <"$FIXTURES/sample-2layer.psd" >"$OUT" 2>/dev/null
    assert_exit0 $? "missing dep exits 0"
    assert_contains "$OUT" "missing dependency" "names the problem"
    assert_contains "$OUT" "ImageMagick" "names the tool"
}

test_flatten_fallback_when_composite_fails() {
    # Shim 'magick': fail whenever the input spec asks for frame [0], defer
    # to the real ImageMagick otherwise — proves the handler retries with
    # -flatten when the composite frame can't be read.
    mkdir -p "$WORK/shim"
    real=$(command -v magick || command -v convert)
    cat >"$WORK/shim/magick" <<EOF
#!/bin/sh
for a in "\$@"; do
    case \$a in *"[0]") echo "shim: no composite frame" >&2; exit 1;; esac
done
exec "$real" "\$@"
EOF
    chmod +x "$WORK/shim/magick"
    PATH="$WORK/shim:$PATH" "$FORGEPEEK" render psd \
        <"$FIXTURES/sample-2layer.psd" >"$OUT" 2>/dev/null
    assert_exit0 $? "fallback path exits 0"
    assert_contains "$OUT" "data:image/png;base64," "flatten fallback produced an image"
    assert_not_contains "$OUT" "forgepeek-error" "no error box after fallback"
}

test_blank_composite_falls_back_to_flatten() {
    # A structurally valid but EMPTY composite frame must not yield a
    # blank preview — the handler measures the render and flattens instead.
    "$FORGEPEEK" render psd <"$FIXTURES/blank-composite.psd" >"$OUT" 2>/dev/null
    assert_exit0 $? "blank-composite psd exits 0"
    assert_contains "$OUT" "data:image/png;base64," "an image was produced"
    if command -v identify >/dev/null 2>&1; then
        sed -n 's/.*base64,\([^"]*\)".*/\1/p' "$OUT" | base64 -d >"$WORK/blank.png"
        sd=$(identify -format '%[fx:standard_deviation]' "$WORK/blank.png")
        if awk -v s="$sd" 'BEGIN { exit !(s + 0 < 0.0005) }'; then
            fail "preview is blank (sd=$sd) — flatten fallback did not trigger"
        fi
    fi
}

test_conversion_timeout_error_box() {
    # Shim ImageMagick with a hang; a 1-second budget must produce the
    # graceful error box, not a stuck or blank page.
    mkdir -p "$WORK/hang"
    printf '#!/bin/sh\nsleep 30\n' >"$WORK/hang/magick"
    chmod +x "$WORK/hang/magick"
    start=$(date +%s)
    PATH="$WORK/hang:$PATH" FORGEPEEK_TIMEOUT=1 "$FORGEPEEK" render psd \
        <"$FIXTURES/sample-2layer.psd" >"$OUT" 2>/dev/null
    rc=$?
    elapsed=$(( $(date +%s) - start ))
    assert_exit0 $rc "timeout exits 0"
    assert_contains "$OUT" "forgepeek-error" "error box after timeout"
    if [ "$elapsed" -gt 10 ]; then
        fail "timeout not enforced (took ${elapsed}s)"
    fi
}

run_tests
