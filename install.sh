#!/bin/sh
# forgepeek installer — idempotent, re-run for upgrades.
#
# Docker layout (standard Forgejo image with a /data volume):
#   ./install.sh docker [--container forgejo] [--dest /data/forgepeek]
#
# Bare metal:
#   ./install.sh baremetal [--libdir /usr/local/lib/forgepeek] [--bindir /usr/local/bin]
#
# Both modes copy the dispatcher + handlers/ + lib/, verify handler
# dependencies where the renderers will actually run, and print the exact
# app.ini stanzas to append. Nothing is written to app.ini automatically.
set -u

SRC=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)
FILES="forgepeek handlers lib"

die() { printf 'install.sh: %s\n' "$*" >&2; exit 1; }

sanity_check_src() {
    [ -x "$SRC/forgepeek" ] || die "run from a forgepeek checkout ($SRC/forgepeek not found)"
    [ -f "$SRC/lib/viewer.js" ] || die "lib/viewer.js missing — this checkout is incomplete"
}

print_snippet() { # print_snippet DIR  (directory containing the forgepeek command)
    cat <<EOF

============================================================
1. Append the following to your app.ini (custom/conf/app.ini
   inside the container, or /etc/forgejo/app.ini on bare metal),
   AFTER removing any previous forgepeek stanzas:
============================================================
EOF
    "$SRC/forgepeek" config --path "$1"
    cat <<'EOF'

============================================================
2. Restart Forgejo so it re-reads app.ini:
     docker:      docker compose restart forgejo   (or docker restart <name>)
     bare metal:  systemctl restart forgejo
3. Open any .psd/.eps/.stl/... file in the web UI to verify.
   Troubleshooting: docs/INSTALL.md
============================================================
EOF
}

install_docker() {
    CONTAINER=forgejo
    DEST=/data/forgepeek
    while [ $# -gt 0 ]; do
        case $1 in
            --container) CONTAINER=$2; shift 2 ;;
            --dest)      DEST=$2; shift 2 ;;
            *) die "unknown docker option: $1" ;;
        esac
    done
    case $DEST in
        */forgepeek) ;;
        *) die "--dest must end in /forgepeek (got: $DEST)" ;;
    esac

    command -v docker >/dev/null 2>&1 || die "docker CLI not found"
    docker inspect "$CONTAINER" >/dev/null 2>&1 || \
        die "container '$CONTAINER' not found (use --container <name>)"

    echo "Installing into container '$CONTAINER' at $DEST ..."
    # Fresh copy each run so removed handlers don't linger (upgrade-safe:
    # nothing but forgepeek's own files live under $DEST).
    docker exec "$CONTAINER" rm -rf "$DEST" || die "could not clean $DEST"
    docker exec "$CONTAINER" mkdir -p "$DEST" || die "could not create $DEST"
    for f in $FILES; do
        docker cp "$SRC/$f" "$CONTAINER:$DEST/" || die "docker cp $f failed"
    done

    echo "Verifying handler dependencies inside the container ..."
    if ! docker exec "$CONTAINER" "$DEST/forgepeek" check; then
        cat <<'EOF'

Some dependencies are missing INSIDE the container. Options (pick one):
  a) Derived image (recommended — survives container recreation):
     see Dockerfile.example in this repo, or add a `build:` block to
     your compose file.
  b) Quick but non-durable — packages vanish when the container is
     recreated (e.g. after `docker compose pull`):
       docker exec <container> apk add --no-cache imagemagick ghostscript
The stl/fbx handlers need no extra packages and work either way.
EOF
    fi

    print_snippet "$DEST"
    printf 'NOTE: %s lives on the Forgejo data volume, so the files survive\n' "$DEST"
    printf 'container recreation. Re-run this installer to upgrade.\n'
}

install_baremetal() {
    LIBDIR=/usr/local/lib/forgepeek
    BINDIR=/usr/local/bin
    while [ $# -gt 0 ]; do
        case $1 in
            --libdir) LIBDIR=$2; shift 2 ;;
            --bindir) BINDIR=$2; shift 2 ;;
            *) die "unknown baremetal option: $1" ;;
        esac
    done
    case $LIBDIR in
        */forgepeek) ;;
        *) die "--libdir must end in /forgepeek (got: $LIBDIR)" ;;
    esac

    parent=$(dirname "$LIBDIR")
    mkdir -p "$parent" "$BINDIR" 2>/dev/null || true
    [ -w "$parent" ] || die "cannot write to $parent — re-run with sudo"
    [ -w "$BINDIR" ] || die "cannot write to $BINDIR — re-run with sudo"

    echo "Installing to $LIBDIR ..."
    rm -rf "$LIBDIR"
    mkdir -p "$LIBDIR"
    for f in $FILES; do
        cp -R "$SRC/$f" "$LIBDIR/" || die "copy of $f failed"
    done
    ln -sf "$LIBDIR/forgepeek" "$BINDIR/forgepeek"

    echo "Verifying handler dependencies on this host ..."
    "$BINDIR/forgepeek" check || cat <<'EOF'

Some dependencies are missing. Install them with your package manager,
e.g.:  apt install imagemagick ghostscript
  or:  apk add imagemagick ghostscript
The stl/fbx handlers need no extra packages.
EOF

    # RENDER_COMMAND uses the $BINDIR symlink; the dispatcher resolves it
    # back to $LIBDIR to find its handlers.
    print_snippet "$BINDIR"
}

sanity_check_src
case "${1:-}" in
    docker)    shift; install_docker "$@" ;;
    baremetal) shift; install_baremetal "$@" ;;
    *)
        sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'
        exit 2
        ;;
esac
