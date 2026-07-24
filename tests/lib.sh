# Shared helpers for forgepeek tests. POSIX sh; sourced by tests/test_*.sh.
# A test script defines test_* functions; run_tests executes each in order.

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)
FORGEPEEK="$ROOT/forgepeek"
FIXTURES="$ROOT/tests/fixtures"

TESTS_RUN=0
TESTS_FAILED=0
CURRENT_TEST=''

fail() {
    TESTS_FAILED=$((TESTS_FAILED + 1))
    printf 'FAIL %s: %s\n' "$CURRENT_TEST" "$1" >&2
}

# assert_contains HAYSTACK_FILE NEEDLE DESC
assert_contains() {
    if ! grep -q -- "$2" "$1"; then
        fail "$3 (expected output to contain: $2)"
    fi
}

assert_not_contains() {
    if grep -q -- "$2" "$1"; then
        fail "$3 (expected output NOT to contain: $2)"
    fi
}

assert_exit0() { # assert_exit0 STATUS DESC
    if [ "$1" -ne 0 ]; then
        fail "$2 (expected exit 0, got $1)"
    fi
}

# make_restricted_path — build a bin dir holding only coreutils/shell basics
# (no magick/convert/gs), print its path. Used for missing-dependency tests.
make_restricted_path() {
    _rp_dir=$1
    mkdir -p "$_rp_dir"
    for _rp_t in sh dash sed head tail cat wc tr awk base64 mktemp rm mv \
                 dirname basename readlink grep sort ls timeout gzip; do
        _rp_p=$(command -v "$_rp_t" 2>/dev/null) || continue
        ln -sf "$_rp_p" "$_rp_dir/$_rp_t"
    done
    printf '%s\n' "$_rp_dir"
}

run_tests() {
    _rt_names=$(grep -o '^test_[A-Za-z0-9_]*' "$0")
    for _rt_t in $_rt_names; do
        CURRENT_TEST=$_rt_t
        TESTS_RUN=$((TESTS_RUN + 1))
        _rt_before=$TESTS_FAILED
        "$_rt_t"
        if [ "$TESTS_FAILED" -eq "$_rt_before" ]; then
            printf 'ok   %s\n' "$_rt_t"
        fi
    done
    printf '%s: %d tests, %d failed\n' "$(basename "$0")" "$TESTS_RUN" "$TESTS_FAILED"
    [ "$TESTS_FAILED" -eq 0 ]
}
