# Forgejo iframe render URL fix

Works around a Forgejo bug (present through v16.0.1, unfixed upstream as of
2026-07-24) where **binary** files rendered by an iframe-mode external
renderer — forgepeek's `.stl`/`.fbx`, or any other — get a broken iframe URL
with an empty ref segment (`/owner/repo/render//path` → 404 → gray broken
box). Text files are unaffected because Forgejo's text path populates the
`BranchNameSubURL` meta that the iframe URL is built from; the binary path
(`routers/web/repo/view.go`, second `markupRender` call site) does not.

`footer.tmpl` is a [custom template](https://forgejo.org/docs/latest/admin/customization/)
injected before `</body>` on every page. When it finds an `iframe.external-render`
whose src contains `/render//`, it rebuilds the correct URL from the file
view's raw/download link (which Forgejo generates correctly) and re-runs the
iframe height handshake. On healthy pages it does nothing.

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
