# Adding a handler

A handler is one executable POSIX-shell file in `handlers/`. Adding a format requires **no dispatcher changes**: drop the file in, re-run `forgepeek config`, append the new stanzas to `app.ini`, restart Forgejo.

## The contract

Every handler MUST:

1. **Declare metadata** in a machine-readable comment header (parsed by the dispatcher, `forgepeek config`, `forgepeek check`, and the installer):

   ```sh
   # forgepeek:extensions = .foo,.bar     # comma-separated, with dots
   # forgepeek:mode = sanitized           # or: iframe
   # forgepeek:deps = sometool|alttool    # comma list; '|' = alternatives;
   #                                      # empty/omitted = coreutils only
   # forgepeek:desc = One-line description
   ```

2. **Read the file from stdin** and **write HTML to stdout**. The dispatcher passes the matched extension (lowercase, no dot) as `$1` — that's how one handler serves several extensions differently. There is no filename; Forgejo doesn't send one.

3. **Always exit 0.** On any failure emit `fp_error_box` — a non-zero exit makes Forgejo display a worse generic error. This includes the "can't happen" paths.

4. **Guard everything**: size-cap stdin *before* converting (`fp_slurp_stdin`), run conversions under the timeout (`fp_run_timeout`), check dependencies before use (`fp_have` / `fp_imagemagick` → `fp_missing_dep_box`), cap output pixel dimensions (`FORGEPEEK_MAX_EDGE`), and put captured stderr in the error box's `<details>`.

5. **Treat input as hostile.** Never place file *content* in a command line, environment variable, or eval — bytes move only via stdin/pipes/temp-file *paths*. Temp files come from `fp_tmpdir` (auto-cleaned; call it directly, never in `$(...)`).

6. **Be dash-compatible.** No bashisms; `dash -n handlers/yours` must pass, and the test suite runs everything under dash.

Sanitized-mode handlers must only emit elements/attributes covered by the generated sanitizer rules (`div`, `p`, `strong`, `details`, `summary`, `pre`, `img` with `class`/`style`/data-URI `src` — see `lib/config.sh`). If you need more, extend `fp_emit_sanitizer` in the same change. Iframe-mode handlers emit a complete self-contained HTML document instead — no external fetches (the sandbox has no same-origin and air-gapped instances have no internet).

## Template: static image (sanitized mode)

```sh
#!/bin/sh
# forgepeek handler: Example raster format
# forgepeek:extensions = .xyz
# forgepeek:mode = sanitized
# forgepeek:deps = xyztool
# forgepeek:desc = Example XYZ raster image

set -u
. "$FORGEPEEK_LIB/common.sh"

ext=${1:-xyz}

fp_tmpdir || exit 0                     # never $(fp_tmpdir) — trap scoping
in="$FP_TMPDIR/input.$ext"
out="$FP_TMPDIR/out.png"
log="$FP_TMPDIR/stderr.log"

# 1. size guard (before any conversion work)
if ! fp_slurp_stdin "$in" "$FORGEPEEK_MAX_BYTES"; then
    fp_too_large_box "$(fp_file_size "$in")" "$FORGEPEEK_MAX_BYTES"
    exit 0
fi
[ -s "$in" ] || { fp_error_box "empty file" "The file has no content to preview."; exit 0; }

# 2. dependency guard
if ! fp_have xyztool; then
    fp_missing_dep_box "$ext" "xyztool"
    exit 0
fi

# 3. convert under timeout, stderr captured; pixel cap included
if ! fp_run_timeout "$log" xyztool --to-png --max-edge "$FORGEPEEK_MAX_EDGE" \
        "$in" "$out" || [ ! -s "$out" ]; then
    fp_error_box "could not convert this $ext file" \
        "xyztool failed to read the file." "$log"
    exit 0
fi

# 4. responsive <img> with base64 data URI
fp_img_html "$out" "$ext preview (rendered by forgepeek)"
exit 0
```

## Template: interactive viewer (iframe mode)

For formats parsed client-side (like the 3D handlers). The page must be fully self-contained; `lib/3d.sh` does the heavy lifting for anything the three.js bundle can load — a new mesh format supported by an existing three.js loader is mostly a matter of extending `viewer/src/viewer.js` and rebuilding the bundle (`sh viewer/build.sh`, commit the result).

```sh
#!/bin/sh
# forgepeek handler: Example 3D format
# forgepeek:extensions = .xyz
# forgepeek:mode = iframe
# forgepeek:deps =
# forgepeek:desc = Example XYZ 3D model, interactive viewer

set -u
. "$FORGEPEEK_LIB/common.sh"
. "$FORGEPEEK_LIB/3d.sh"

fp_tmpdir || exit 0
in="$FP_TMPDIR/input.xyz"

# 3D uses its own (larger) cap; the too-large notice is rendered by the
# page's own JS so it's styled like every other viewer message.
if ! fp_slurp_stdin "$in" "$FORGEPEEK_MAX_BYTES_3D"; then
    fp_3d_page_too_large xyz "$(fp_file_size "$in")" "$FORGEPEEK_MAX_BYTES_3D"
    exit 0
fi

# Emits the complete HTML document: inline CSS + viewer bundle + the model
# as base64, decoded and parsed client-side ('xyz' must be a format the
# viewer's parseModel() knows).
fp_3d_page xyz "$in"
exit 0
```

Note the split: server-side failures (size cap) still produce a page; *parse* failures are detected client-side by the viewer JS, which shows its own error box. Your `parseModel()` addition must throw on bad input, and geometry-less results are treated as errors.

## Tests

Add `tests/test_<name>.sh` following the existing ones, with at minimum:

- valid fixture → expected HTML (data URI, or round-tripping embedded base64)
- oversized input (`FORGEPEEK_MAX_BYTES=100 …`) → "too large" message
- corrupt fixture → error box, exit 0
- missing dependency (`make_restricted_path`) → clear message, exit 0

Generate fixtures programmatically in `tests/fixtures/generate.sh` (keep each under ~100 KB, committed). Run everything with `sh tests/run.sh`.
