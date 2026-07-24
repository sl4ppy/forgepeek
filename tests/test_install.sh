#!/bin/sh
# Installer: bare-metal mode into a temp prefix, idempotent re-run, correct
# snippet paths. (Docker mode needs a docker daemon — covered by
# tests/integration-manual.md.)
set -u
. "$(dirname -- "$0")/lib.sh"

OUT=$(mktemp) && WORK=$(mktemp -d) && trap 'rm -rf "$OUT" "$WORK"' EXIT

test_baremetal_install() {
    sh "$ROOT/install.sh" baremetal \
        --libdir "$WORK/lib/forgepeek" --bindir "$WORK/bin" >"$OUT" 2>&1
    assert_exit0 $? "install succeeds"
    [ -x "$WORK/lib/forgepeek/forgepeek" ] || fail "dispatcher not installed"
    [ -f "$WORK/lib/forgepeek/lib/viewer.js" ] || fail "viewer bundle not installed"
    [ -L "$WORK/bin/forgepeek" ] || fail "bin symlink missing"
    assert_contains "$OUT" "\[markup.forgepeek_psd\]" "snippet printed"
    assert_contains "$OUT" "RENDER_COMMAND = \"$WORK/bin/forgepeek render psd\"" \
        "snippet uses installed path"
}

test_installed_copy_works_via_symlink() {
    sh "$ROOT/install.sh" baremetal \
        --libdir "$WORK/lib/forgepeek" --bindir "$WORK/bin" >/dev/null 2>&1
    "$WORK/bin/forgepeek" render psd <"$FIXTURES/sample-2layer.psd" >"$OUT" 2>/dev/null
    assert_exit0 $? "installed dispatcher renders"
    assert_contains "$OUT" "data:image/png;base64," "handlers found through symlink"
}

test_reinstall_is_idempotent_and_prunes() {
    sh "$ROOT/install.sh" baremetal \
        --libdir "$WORK/lib/forgepeek" --bindir "$WORK/bin" >/dev/null 2>&1
    touch "$WORK/lib/forgepeek/handlers/stale-handler"
    sh "$ROOT/install.sh" baremetal \
        --libdir "$WORK/lib/forgepeek" --bindir "$WORK/bin" >"$OUT" 2>&1
    assert_exit0 $? "re-run succeeds"
    if [ -e "$WORK/lib/forgepeek/handlers/stale-handler" ]; then
        fail "stale files survive reinstall"
    fi
}

test_libdir_guard() {
    if sh "$ROOT/install.sh" baremetal --libdir "$WORK/oops" \
        --bindir "$WORK/bin" >"$OUT" 2>&1; then
        fail "should refuse --libdir not ending in /forgepeek"
    fi
    assert_contains "$OUT" "must end in /forgepeek" "explains the guard"
}

run_tests
