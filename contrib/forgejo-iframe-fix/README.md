# Forgejo page enhancements & iframe render fixes

Besides the bug workarounds below, `footer.tmpl` adds **zoom/pan controls to
forgepeek's image previews** (`.psd`/`.eps`/`.ai`): mouse-wheel zoom at the
cursor (up to 32×), drag to pan, double-click to toggle, and a +/−/reset
overlay. Sanitized-mode renderer output cannot carry JavaScript — Forgejo
strips it — so the interaction has to live in the parent page; without this
template the previews are simply static images.


Works around **two** Forgejo bugs (present through v16.0.1, unfixed upstream
as of 2026-07-24) that break iframe-mode external renderers — forgepeek's
`.stl`/`.fbx`, or any other — for **binary** files. Text files are unaffected
by both.

1. **Broken iframe URL**: the src gets an empty ref segment
   (`/owner/repo/render//path` → 404 → gray broken box). The binary path in
   `routers/web/repo/view.go` (second `markupRender` call site) omits the
   `BranchNameSubURL` meta the URL is built from.
2. **Corrupted renderer input**: `routers/web/repo/render.go` pipes the blob
   through `charset.ToUTF8WithFallbackReader` before the external renderer,
   mangling binary bytes — models fail to parse even though the file is fine.

`footer.tmpl` is a [custom template](https://forgejo.org/docs/latest/admin/customization/)
injected before `</body>` on every page. It rebuilds a broken iframe URL from
the file view's raw/download link (which Forgejo generates correctly), re-runs
the iframe height handshake, and posts the pristine `/raw/` bytes into the
viewer via `postMessage` — forgepeek's viewer re-renders with them when its
embedded copy failed to parse or differs in size. On healthy pages it does
nothing. (The byte hand-off requires forgepeek's viewer; for other people's
iframe renderers only the URL fix applies.)

## Install (Docker, one-time — survives container recreation)

The custom template dir lives on the data volume, so a single console command
is durable:

```sh
mkdir -p /data/gitea/templates/custom \
  && wget -qO /data/gitea/templates/custom/footer.tmpl \
     https://raw.githubusercontent.com/sl4ppy/forgepeek/main/contrib/forgejo-iframe-fix/footer.tmpl
```

then restart Forgejo. If you already have a `custom/footer.tmpl`, append the
`<script>` block from this file to it instead.

Bare metal: place it at `$FORGEJO_CUSTOM/templates/custom/footer.tmpl`
(commonly `/var/lib/forgejo/custom/templates/custom/footer.tmpl`).

## Related: X-Frame-Options must not be DENY

Independently of the URL bug, the render page can only be embedded if
`X-Frame-Options` allows same-origin framing. Forgejo's default is
`SAMEORIGIN`, which works. If your `app.ini` (`[cors] X_FRAME_OPTIONS`) or
your reverse proxy sets `DENY`, every iframe-mode preview shows a gray
broken box regardless of this fix — set it back to `SAMEORIGIN` (env form:
`FORGEJO__cors__X_FRAME_OPTIONS=SAMEORIGIN`) or scope your proxy's header
off the `/{owner}/{repo}/render/` paths.

Remove `footer.tmpl` once the bug is fixed in your Forgejo version.
