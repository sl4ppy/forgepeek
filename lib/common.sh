# forgepeek common library — sourced by every handler.
# POSIX sh (dash-compatible). No bashisms.
#
# Contract for handlers (see docs/ADDING-HANDLERS.md):
#   - input arrives on stdin, HTML goes to stdout
#   - ALWAYS exit 0, even on failure: emit fp_error_box instead
#   - never interpolate file content into commands; pass data via files/pipes

# ---- tunables (env-overridable) --------------------------------------------
FORGEPEEK_MAX_BYTES="${FORGEPEEK_MAX_BYTES:-52428800}"        # 50 MB
FORGEPEEK_MAX_BYTES_3D="${FORGEPEEK_MAX_BYTES_3D:-104857600}" # 100 MB
FORGEPEEK_TIMEOUT="${FORGEPEEK_TIMEOUT:-30}"                  # seconds
FORGEPEEK_MAX_EDGE="${FORGEPEEK_MAX_EDGE:-2000}"              # px, longest edge

# ---- temp workspace ---------------------------------------------------------
# fp_tmpdir: create a private temp dir (removed on exit) and set FP_TMPDIR.
# Must be called directly, NOT in $(...) — the cleanup trap belongs to the
# handler's shell, and a command substitution would run it in a subshell.
fp_tmpdir() {
    if [ -z "${FP_TMPDIR:-}" ]; then
        FP_TMPDIR=$(mktemp -d "${TMPDIR:-/tmp}/forgepeek.XXXXXX") || return 1
        trap 'rm -rf "$FP_TMPDIR"' EXIT INT TERM
    fi
}

# ---- HTML helpers -----------------------------------------------------------
fp_html_escape() {
    sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' \
        -e 's/"/\&quot;/g' -e "s/'/\&#39;/g"
}

# fp_error_box TITLE MESSAGE [DETAIL_FILE]
# Friendly error box; DETAIL_FILE (e.g. captured stderr) shown in <details>.
fp_error_box() {
    _fp_title=$1
    _fp_msg=$2
    _fp_detail=${3:-}
    printf '<div class="forgepeek forgepeek-error" style="border:1px solid #d1242f;border-radius:6px;padding:12px 16px;margin:8px 0;background:#fff5f5;color:#24292f;font-family:sans-serif">\n'
    printf '<p style="margin:0 0 4px 0"><strong>&#9888; forgepeek: %s</strong></p>\n' \
        "$(printf '%s' "$_fp_title" | fp_html_escape)"
    printf '<p style="margin:0">%s</p>\n' \
        "$(printf '%s' "$_fp_msg" | fp_html_escape)"
    if [ -n "$_fp_detail" ] && [ -s "$_fp_detail" ]; then
        printf '<details style="margin-top:8px"><summary>tool output</summary>\n'
        printf '<pre style="overflow-x:auto;background:#f6f8fa;padding:8px;border-radius:4px">%s</pre>\n' \
            "$(head -c 4096 "$_fp_detail" | fp_html_escape)"
        printf '</details>\n'
    fi
    printf '</div>\n'
}

# fp_info_box TITLE MESSAGE — neutral notice (e.g. file too large).
fp_info_box() {
    printf '<div class="forgepeek forgepeek-notice" style="border:1px solid #d0d7de;border-radius:6px;padding:12px 16px;margin:8px 0;background:#f6f8fa;color:#24292f;font-family:sans-serif">\n'
    printf '<p style="margin:0 0 4px 0"><strong>%s</strong></p>\n' \
        "$(printf '%s' "$1" | fp_html_escape)"
    printf '<p style="margin:0">%s</p>\n' \
        "$(printf '%s' "$2" | fp_html_escape)"
    printf '</div>\n'
}

# ---- input handling ---------------------------------------------------------
# fp_slurp_stdin OUTFILE MAXBYTES
# Copy stdin to OUTFILE, stopping after MAXBYTES+1 bytes; drain the rest so
# the writer never sees a broken pipe. Returns 1 (after draining) if the
# input exceeded MAXBYTES; caller should then emit fp_too_large_box.
fp_slurp_stdin() {
    _fp_out=$1
    _fp_max=$2
    head -c "$((_fp_max + 1))" >"$_fp_out"
    cat >/dev/null 2>&1 || true
    [ "$(fp_file_size "$_fp_out")" -le "$_fp_max" ]
}

fp_file_size() {
    wc -c <"$1" | tr -d ' '
}

# fp_mb BYTES — pretty-print a byte count as MB with one decimal.
fp_mb() {
    awk "BEGIN { printf \"%.1f\", $1 / 1048576 }"
}

# fp_too_large_box ACTUAL_BYTES LIMIT_BYTES
fp_too_large_box() {
    fp_info_box "File too large to preview ($(fp_mb "$1") MB)" \
        "The preview limit is $(fp_mb "$2") MB. Download the file to view it."
}

# ---- external tools ---------------------------------------------------------
# fp_run_timeout LOGFILE CMD [ARGS...] — run CMD with stderr captured to
# LOGFILE and a wall-clock limit of FORGEPEEK_TIMEOUT seconds (if timeout(1)
# exists). Returns the command's exit status; 124 means timed out.
fp_run_timeout() {
    _fp_log=$1
    shift
    if command -v timeout >/dev/null 2>&1; then
        timeout "$FORGEPEEK_TIMEOUT" "$@" 2>>"$_fp_log"
    else
        "$@" 2>>"$_fp_log"
    fi
}

# fp_have TOOL... — succeed if at least one of the listed tools exists.
fp_have() {
    for _fp_t in "$@"; do
        command -v "$_fp_t" >/dev/null 2>&1 && return 0
    done
    return 1
}

# fp_imagemagick — print the ImageMagick entry command (magick or convert).
fp_imagemagick() {
    if command -v magick >/dev/null 2>&1; then
        printf 'magick\n'
    elif command -v convert >/dev/null 2>&1; then
        printf 'convert\n'
    else
        return 1
    fi
}

# fp_missing_dep_box HANDLER TOOLS_HINT
fp_missing_dep_box() {
    fp_error_box "missing dependency for the '$1' handler" \
        "This preview needs $2 installed next to Forgejo (inside the container, if you run one). See the forgepeek install docs."
}

# ---- output -----------------------------------------------------------------
# fp_b64 FILE — base64 without line wraps (portable across GNU/busybox).
fp_b64() {
    base64 <"$1" | tr -d '\n'
}

# fp_img_html PNG_FILE ALT_TEXT — responsive <img> with a data URI.
fp_img_html() {
    printf '<div class="forgepeek forgepeek-image" style="text-align:center">'
    printf '<img src="data:image/png;base64,%s" alt="%s" style="max-width:100%%;height:auto"/>' \
        "$(fp_b64 "$1")" \
        "$(printf '%s' "$2" | fp_html_escape)"
    printf '</div>\n'
}
