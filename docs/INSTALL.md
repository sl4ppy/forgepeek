# Installing forgepeek

This guide assumes no prior knowledge of Forgejo's external renderers. It covers the two real-world layouts (Docker and bare metal), explains the one step everyone misses (`ALLOW_DATA_URI_IMAGES`), and ends with verification and troubleshooting.

## Background: what an external renderer is

Forgejo has no plugin system. Its extension point for file previews is the *external renderer*: a `[markup.NAME]` section in `app.ini` maps file extensions to a shell command. When you open a matching file in the web UI, Forgejo pipes the file's bytes to that command's stdin and shows the command's stdout as the preview. forgepeek is a set of such commands plus tooling so you never hand-write the config.

Two render modes matter here:

- **`sanitized`** (used for `.psd`/`.psb`/`.eps`/`.ai`): the command's HTML output is run through Forgejo's HTML sanitizer before display. Anything not explicitly whitelisted is stripped — *silently*. Paired `[markup.sanitizer.NAME.*]` sections whitelist elements/attributes, and `ALLOW_DATA_URI_IMAGES = true` is required for embedded base64 images to survive. **Without it, previews render as a blank area with no error.** `forgepeek config` generates all of this.
- **`iframe`** (used for `.stl`/`.fbx`): the output is served as a complete standalone HTML document inside a sandboxed iframe (`allow-scripts`, cross-origin isolated), so the interactive 3D viewer's JavaScript can run. Sanitizer sections don't apply in this mode.

Renders are **not cached** — the command runs on every page view. Renderer commands execute **inside the Forgejo container/host**, so conversion tools must exist there, not on your workstation.

## Version requirements

| Handlers | Minimum version |
|---|---|
| `.psd` `.psb` `.eps` `.ai` (sanitized mode) | any current Forgejo or Gitea (`RENDER_CONTENT_MODE` exists since Gitea 1.16) |
| `.stl` `.fbx` (iframe mode) | **Forgejo ≥ 13.0.1** |

Why 13.0.1: iframe-mode content was invisible (zero height) until [PR #8378](https://codeberg.org/forgejo/forgejo/pulls/8378) (issue [#7586](https://codeberg.org/forgejo/forgejo/issues/7586)), which shipped in 13.0.0 — and 13.0.0 itself had a regression clamping iframes to 300px, fixed in 13.0.1. There are no backports to v12 or earlier. The viewer page also sets its own explicit height as belt-and-suspenders, but on pre-13.0.1 Forgejo the iframe may still collapse.

Check your version: bottom of any Forgejo page, or `docker exec forgejo forgejo --version`.

## Layout A: Docker (standard compose deployment)

Assumptions: the official Forgejo image, a volume or bind mount at `/data` (the standard layout), container named `forgejo`. Adjust `--container` if yours differs.

### 1. Install the files

```sh
git clone https://github.com/sl4ppy/forgepeek.git
cd forgepeek
./install.sh docker --container forgejo
```

This copies `forgepeek`, `handlers/` and `lib/` to `/data/forgepeek` **on the data volume**, so the files survive container recreation and upgrades. Re-run the same command any time to upgrade.

### 2. Get the conversion tools into the container

The installer runs `forgepeek check` inside the container and tells you what's missing. The `.stl`/`.fbx` handlers need nothing; ImageMagick (psd) and Ghostscript (eps) usually aren't in the stock image. Two options:

**Option 1 — derived image (recommended, durable).** Build your own image from the official one; see [`Dockerfile.example`](../Dockerfile.example). With compose:

```yaml
services:
  forgejo:
    build:
      context: ./forgepeek
      dockerfile: Dockerfile.example
    # everything else unchanged
```

**Option 1b — minimal derived image (best with stack managers like Komodo/Portainer).** If you install the forgepeek *files* onto the data volume with `install.sh docker` (step 1), the derived image only needs to supply the packages — two lines, no COPY, and upgrading forgepeek never requires a rebuild:

```dockerfile
FROM codeberg.org/forgejo/forgejo:16
RUN apk add --no-cache imagemagick ghostscript
```

```yaml
services:
  server:
    build: .                      # dir containing the 2-line Dockerfile
    image: forgejo-forgepeek:16   # local tag for the built image
    # rest of the service unchanged
```

**Option 2 — `docker exec` (quick, non-durable):**

```sh
docker exec forgejo apk add --no-cache imagemagick ghostscript
```

Honesty required: packages installed this way live in the container's writable layer and **disappear whenever the container is recreated** — `docker compose pull && up -d`, watchtower, host migration. Previews then break until you re-run the command. Fine for trying forgepeek out; use Option 1 for production.

### 3. Configure app.ini

The installer prints the exact stanzas (regenerate any time with `docker exec forgejo /data/forgepeek/forgepeek config --path /data/forgepeek`). Append them to your `app.ini` — with the standard volume layout that's `<data volume>/gitea/conf/app.ini` on the host, or edit in place:

```sh
docker exec -it forgejo vi /data/gitea/conf/app.ini
```

### 4. Restart and verify

```sh
docker compose restart forgejo
```

Verification is below, after the bare-metal section.

## Layout B: bare metal

```sh
git clone https://github.com/sl4ppy/forgepeek.git
cd forgepeek
sudo ./install.sh baremetal
```

Installs to `/usr/local/lib/forgepeek` with a `/usr/local/bin/forgepeek` symlink, checks dependencies on the host (`apt install imagemagick ghostscript` / `apk add imagemagick ghostscript` as needed), and prints the stanzas. Append them to your `app.ini` (commonly `/etc/forgejo/app.ini`), make sure the file tools are in the *forgejo service user's* PATH, then:

```sh
sudo systemctl restart forgejo
```

## What the generated config means

One stanza per extension (the extension must be baked into the command — Forgejo sends only file bytes, no filename):

```ini
[markup.forgepeek_psd]
ENABLED = true
FILE_EXTENSIONS = .psd
RENDER_COMMAND = "/data/forgepeek/forgepeek render psd"
IS_INPUT_FILE = false          ; file arrives on stdin, no temp file
RENDER_CONTENT_MODE = sanitized
NEED_POSTPROCESS = false       ; don't rewrite #123/@user inside our HTML

[markup.sanitizer.forgepeek_psd.data_uri]
ALLOW_DATA_URI_IMAGES = true   ; THE step everyone misses — without it,
                               ; previews are silently blank

[markup.sanitizer.forgepeek_psd.div_class]
ELEMENT = div                  ; whitelist the exact elements/attributes
ALLOW_ATTR = class             ; forgepeek emits, value-constrained by
REGEXP = "^forgepeek[a-z -]*$" ; REGEXP so nothing else sneaks through
; ... more rules ...
```

The 3D stanzas differ in one line — `RENDER_CONTENT_MODE = iframe` — and carry no sanitizer sections (the sanitizer doesn't apply to iframe content).

## Fully declarative deployment (Komodo, Portainer, GitOps)

If you can't (or don't want to) shell into the Docker host — e.g. your stacks are deployed by [Komodo](https://komo.do) from another machine — the entire install can live in the stack definition. Two ingredients:

**1. A derived image carrying everything** — packages *and* the forgepeek files (`Dockerfile.example` does exactly this; override the base tag with the `FORGEJO_IMAGE` build arg). Point your stack manager's build at a clone/fork of this repo, or vendor it into your stack repo. The files land in `/usr/local/lib/forgepeek`.

**2. The renderer config as environment variables.** The Forgejo image runs `environment-to-ini` at startup, which writes `FORGEJO__section__KEY` variables into `app.ini` — dots in section names encode as `_0X2E_`. Generate the complete block, ready to paste into the service's `environment:` list:

```sh
./forgepeek config --format env --path /usr/local/lib/forgepeek
```

```yaml
services:
  server:
    build:
      context: https://your.host/you/forgepeek.git   # or a local checkout
      dockerfile: Dockerfile.example
      args:
        FORGEJO_IMAGE: codeberg.org/forgejo/forgejo:16
    image: forgejo-forgepeek:16
    pull_policy: build   # local build tag — stops 'compose pull' from
                         # failing on a registry lookup (stack managers
                         # like Komodo run pull before every deploy)
    environment:
      - USER_UID=1000
      - USER_GID=1000
      # ... your existing vars ...
      - 'FORGEJO__MARKUP_0X2E_FORGEPEEK_PSD__ENABLED=true'
      # ... rest of `forgepeek config --format env` output ...
```

Notes:
- `$` appears doubled (`$$`) in the generated regex values — that's compose interpolation escaping, required inside `environment:` lists. If you paste the variables somewhere that does **not** interpolate (a raw `.env` file used via `env_file:`), un-double them.
- The env route is idempotent by design: values are re-applied into `app.ini` on every container start, so redeploys/recreations can never lose the config. Upgrading forgepeek = rebuild the image.
- To verify after deploy, use your manager's container console (or logs): `forgepeek check` should print all `ok`, and the Troubleshooting table below applies unchanged (the render command path is `/usr/local/lib/forgepeek/forgepeek`).

## Verifying it worked

1. Push a test file to any repo — the fixtures in `tests/fixtures/` of this repo are handy (`sample-2layer.psd`, `sample.eps`, `cube-binary.stl`, `cube-ascii.fbx`).
2. Open the file in the web UI:
   - `.psd`/`.eps`: the artwork appears as an image.
   - `.stl`/`.fbx`: an interactive viewer with a grid, a triangle-count badge, and wireframe/reset buttons. Drag to orbit, scroll to zoom.
3. Test the failure path too: rename any text file to `broken.psd`, push, open — you should get a styled "could not convert" box, not a blank page.

From the command line (no browser):

```sh
docker exec -i forgejo /data/forgepeek/forgepeek render psd \
  < tests/fixtures/sample-2layer.psd | grep -c "data:image/png"   # → 1
```

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Preview area is blank (no error, no image) | Sanitizer stripped the output — missing `[markup.sanitizer.*]` rules or `ALLOW_DATA_URI_IMAGES` | Re-run `forgepeek config`, replace all forgepeek stanzas in `app.ini`, restart |
| 3D viewer area blank or zero-height | Forgejo < 13.0.1 (iframe height fix) | Upgrade Forgejo; image handlers still work meanwhile |
| 3D viewer shows a gray box with a broken-page icon (binary `.stl`/`.fbx`); the same file renders at `…/render/branch/<branch>/<path>` directly | Forgejo bug (through v16.0.1 at least): iframe src for **binary** files is missing its ref segment (`/render//…` → 404) | Install [contrib/forgejo-iframe-fix](../contrib/forgejo-iframe-fix/) — one file in `custom/templates/`, survives upgrades |
| Binary `.fbx`/`.stl` shows "could not display … failed to parse" for files that open fine in other tools | Forgejo bug (through v16.0.1 at least): the standalone render route pipes **binary** input through a UTF-8 converter, corrupting it before it reaches the renderer | Same fix: [contrib/forgejo-iframe-fix](../contrib/forgejo-iframe-fix/) v2 posts the pristine `/raw/` bytes into the viewer, which re-renders with them |
| 3D viewer gray broken box AND the direct `…/render/…` URL works but refuses to embed | `X-Frame-Options: DENY` served on the render page — set in `[cors] X_FRAME_OPTIONS` or injected by your reverse proxy | Set `X_FRAME_OPTIONS = SAMEORIGIN` (env: `FORGEJO__cors__X_FRAME_OPTIONS=SAMEORIGIN`), or exclude `/render/` paths from proxy header injection |
| 3D viewer clamped to 300px | Forgejo 13.0.0 exactly (regression #9421) | Upgrade to 13.0.1+ |
| Styled red "could not convert" box | Conversion tool failed — open the box's *tool output* details | Often ImageMagick `policy.xml` denying PSD/EPS rights (see below), or a genuinely broken file |
| "missing dependency" box | Tool not present where Forgejo runs | `docker exec forgejo apk add --no-cache imagemagick ghostscript`, or the derived image |
| Generic Forgejo render error | Renderer crashed before emitting HTML (shouldn't happen — please file a bug) | Check Forgejo logs; run the render command manually with the file on stdin |
| Worked, then broke after `docker compose pull` | exec-installed packages were lost with the old container | Use the derived image ([`Dockerfile.example`](../Dockerfile.example)) — `/data/forgepeek` itself survives; only the apk packages vanish |
| Nothing happens at all (raw/binary view) | Stanzas not loaded: wrong `app.ini` edited, Forgejo not restarted, or extension casing | Restart; check `docker exec forgejo /data/forgepeek/forgepeek list`; confirm the stanza names match |
| File just shows a "View raw" link, no preview attempt | File exceeds **Forgejo's** `[ui] MAX_DISPLAY_FILE_SIZE` (8 MiB default) — checked before any renderer runs | Raise it, e.g. `FORGEJO__ui__MAX_DISPLAY_FILE_SIZE=67108864` (64 MiB); forgepeek's own `FORGEPEEK_MAX_BYTES*` caps still apply after |
| A specific renderer stops matching after a restart, works after another | Two `[markup.*]` sections claim the same extension (e.g. a leftover experiment); registration order is unstable | `grep "\[markup" app.ini` and delete the stale section |

## Optional: zoom controls for image previews

Install [contrib/forgejo-iframe-fix](../contrib/forgejo-iframe-fix/) (the
same custom `footer.tmpl` that fixes the iframe bugs) and the `.psd`/`.eps`/`.ai`
previews gain wheel-zoom at the cursor, drag-pan, double-click toggle, and a
+/−/reset overlay. Sanitized renderer output can't carry JavaScript, so this
enhancement has to live in a page template; previews stay static without it.

## Tuning

Environment variables read by the handlers (set them in the Forgejo container/service environment):

| Variable | Default | Meaning |
|---|---|---|
| `FORGEPEEK_MAX_BYTES` | 52428800 (50 MB) | Max input size for image handlers; larger files get a "too large" notice |
| `FORGEPEEK_MAX_BYTES_3D` | 104857600 (100 MB) | Same, for the 3D handlers (meshes are big) |
| `FORGEPEEK_TIMEOUT` | 30 | Conversion timeout in seconds |
| `FORGEPEEK_MAX_EDGE` | 2000 | Longest edge of rendered preview images, in px |

## Security notes

- Renderer commands run **server-side against user-supplied content**. forgepeek treats input as hostile: file bytes travel only through pipes and private temp files, never through command lines or shell interpolation, and handlers always exit 0 with inert HTML rather than leaking failures.
- You are, however, trusting **ImageMagick's and Ghostscript's parsers** with that hostile input. Both have had RCEs. Keep them updated (a reason to prefer the derived image: rebuilds pick up fixed packages).
- Ghostscript runs with `-dSAFER` (file-access lockdown).
- Some distros' ImageMagick `policy.xml` *disables* PSD or EPS coders (`<policy domain="coder" rights="none" pattern="PSD" />`). If conversions fail with a policy error in the tool output, grant `rights="read"` for PSD — and note forgepeek's EPS path doesn't need IM's EPS coder at all (it calls Ghostscript directly).
- The sanitized-mode rules whitelist only forgepeek's own elements, with attribute values constrained by regex. The iframe mode relies on Forgejo's sandboxed, cross-origin-isolated iframe; the viewer pages are fully self-contained and make no network requests.
- Renders run on every view with no cache; the size caps and timeouts are your DoS guard. Lower them on busy public instances.
