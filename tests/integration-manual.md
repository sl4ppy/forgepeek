# Manual integration test plan

End-to-end verification against a real Forgejo instance. Written for
forgejo.vdlan.com but works against any instance ≥ 13.0.1. Use a scratch
repository — the fixtures are tiny and safe to push anywhere.

Automated equivalents exist below each step where possible; the headless
pieces (`tests/run.sh`, `tests/smoke_viewer.sh`) already cover handler and
viewer behavior — this plan verifies the *Forgejo wiring*: app.ini parsing,
sanitizer behavior, iframe sizing, and the container environment.

## Prerequisites

- forgepeek installed in the container and stanzas appended to `app.ini`
  (see docs/INSTALL.md), Forgejo restarted since.
- A scratch repo, e.g. `https://forgejo.vdlan.com/<you>/forgepeek-test`.
- This checkout locally (for the fixtures).

## 1. Sanity: renderer wiring (no browser)

```sh
docker exec forgejo /data/forgepeek/forgepeek list
# expect four handlers with extensions/modes

docker exec forgejo /data/forgepeek/forgepeek check
# expect all 'ok'; MISSING means deps didn't reach the container (INSTALL.md)

docker exec -i forgejo /data/forgepeek/forgepeek render psd \
  < tests/fixtures/sample-2layer.psd | grep -c "data:image/png;base64,"
# expect: 1
```

## 2. Push the fixtures

```sh
cd "$(mktemp -d)"
git init -q preview-test && cd preview-test
cp <forgepeek-checkout>/tests/fixtures/sample-2layer.psd .
cp <forgepeek-checkout>/tests/fixtures/sample-cmyk.psd .
cp <forgepeek-checkout>/tests/fixtures/sample.psb .
cp <forgepeek-checkout>/tests/fixtures/sample.eps .
cp <forgepeek-checkout>/tests/fixtures/sample.ai .
cp <forgepeek-checkout>/tests/fixtures/cube-binary.stl .
cp <forgepeek-checkout>/tests/fixtures/tetra-ascii.stl .
cp <forgepeek-checkout>/tests/fixtures/cube-ascii.fbx .
cp <forgepeek-checkout>/tests/fixtures/corrupt.psd broken.psd
git add -A && git commit -qm "forgepeek fixtures"
git remote add origin https://forgejo.vdlan.com/<you>/forgepeek-test.git
git push -u origin main
```

## 3. Browser checks

Open each file in the repo's web UI and verify:

| File | Expect |
|---|---|
| `sample-2layer.psd` | red/yellow gradient with a blue square, as an image |
| `sample-cmyk.psd` | green/white gradient with correct (not inverted/dull) colors — proves CMYK→sRGB |
| `sample.psb` | plasma-fractal image |
| `sample.eps` | red square containing a blue square |
| `sample.ai` | same artwork (renders via the PDF path) |
| `cube-binary.stl` | interactive viewer: cube on a grid, "12 triangles · 36 vertices" badge; drag orbits, scroll zooms, wireframe button toggles, reset view reframes |
| `tetra-ascii.stl` | viewer with "4 triangles" |
| `cube-ascii.fbx` | viewer with cube (12 triangles), neutral gray material |
| `broken.psd` | styled red "could not convert" box with a *tool output* details fold — **not** a blank area, **not** a Forgejo error page |

Also check: with your OS/browser in dark mode, the 3D viewer background is dark; the viewer area is roughly 70% of viewport height, never a thin strip (if it's ~0 or exactly 300px tall, see the version table in INSTALL.md).

## 4. Sanitizer regression check (curl)

```sh
TOKEN=<forgejo access token>
curl -s -H "Authorization: token $TOKEN" \
  "https://forgejo.vdlan.com/api/v1/repos/<you>/forgepeek-test/contents/sample-2layer.psd" >/dev/null  # api sanity

curl -s "https://forgejo.vdlan.com/<you>/forgepeek-test/src/branch/main/sample-2layer.psd" \
  | grep -c 'data:image/png;base64,'
# expect ≥ 1. Zero with a 200 page = sanitizer stripped the img → the
# ALLOW_DATA_URI_IMAGES / sanitizer stanzas are missing or misparsed.

curl -s "https://forgejo.vdlan.com/<you>/forgepeek-test/src/branch/main/cube-binary.stl" \
  | grep -c 'iframe'
# expect ≥ 1 (the file view embeds the render in a sandboxed iframe)
```

## 5. Guards in situ

```sh
# size cap (temporarily set a tiny cap; restore after)
docker exec -i -e FORGEPEEK_MAX_BYTES=1024 forgejo \
  /data/forgepeek/forgepeek render psd \
  < tests/fixtures/sample-2layer.psd | grep -c "too large"   # → 1

# timeout wiring exists in the container
docker exec forgejo sh -c 'command -v timeout'               # → a path
```

## 6. Durability (Docker only)

After the next `docker compose pull && docker compose up -d`:

- `/data/forgepeek` must still exist (volume) → `docker exec forgejo ls /data/forgepeek`
- `forgepeek check` again: if tools went MISSING, you're on exec-installed
  packages — switch to the derived image (Dockerfile.example).
