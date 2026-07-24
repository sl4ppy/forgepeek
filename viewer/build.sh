#!/bin/sh
# Build lib/viewer.js from viewer/src/viewer.js. Dev-time only — the result
# is committed so installing forgepeek never requires Node.
set -eu
cd "$(dirname -- "$0")"

if [ ! -d node_modules ]; then
    if [ -f package-lock.json ]; then npm ci; else npm install; fi
fi

npx esbuild src/viewer.js \
    --bundle \
    --minify \
    --format=iife \
    --global-name=ForgePeekViewer \
    --target=es2019 \
    --legal-comments=none \
    --outfile=../lib/viewer.js

printf 'lib/viewer.js: %s bytes\n' "$(wc -c < ../lib/viewer.js)"
