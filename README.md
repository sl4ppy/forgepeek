# forgepeek

**In-browser previews for binary files your Forgejo (or Gitea) can't display natively.**

Click a `.psd` in your repo and see the artwork instead of *"binary file not shown"*. Click an `.stl` and orbit the model in an interactive 3D viewer — right in the file view.

> 📷 *screenshot placeholder: PSD preview and STL viewer side by side*

forgepeek is a collection of [external renderers](https://forgejo.org/docs/latest/admin/external-renderers/): small POSIX-shell handlers behind one dispatcher, installed next to Forgejo and wired up with a few generated lines of `app.ini`. Forgejo has no plugin system — this is the supported extension mechanism, and forgepeek does the fiddly parts (sanitizer rules, iframe mode, error handling) for you.

## Supported formats

| Format | Extensions | Server dependencies | Notes |
|---|---|---|---|
| Photoshop | `.psd`, `.psb` | ImageMagick | Renders the embedded composite; falls back to flattening layers for files saved without "Maximize Compatibility". CMYK converted to sRGB. |
| PostScript | `.eps`, `.ai` | Ghostscript | Runs with `-dSAFER`. Modern (PDF-compatible) and classic `.ai` both work. First page only. |
| STL | `.stl` | **none** | Interactive 3D viewer (three.js, self-contained — works on air-gapped instances). Binary and ASCII. |
| FBX | `.fbx` | **none** | Same viewer. Geometry + materials; textures are best-effort — external texture references can't load inside the sandboxed iframe, so affected meshes fall back to a neutral material. |

The 3D handlers need no conversion tools at all — a bonus if you can't (or won't) install packages in your Forgejo container. All handlers cap input size (`FORGEPEEK_MAX_BYTES`, 50 MB; `FORGEPEEK_MAX_BYTES_3D`, 100 MB), time out stuck conversions, and render a friendly error box instead of ever breaking the page.

**Version requirements:** any reasonably current Forgejo or Gitea for the image handlers; **Forgejo ≥ 13.0.1** for the 3D viewers (earlier versions render iframe content with zero height — details in [docs/INSTALL.md](docs/INSTALL.md)).

## Quick start (Docker)

For a standard `docker compose` Forgejo with a `/data` volume:

```sh
git clone https://example.com/forgepeek/forgepeek.git
cd forgepeek
./install.sh docker --container forgejo
```

The installer copies forgepeek onto the data volume, checks that ImageMagick/Ghostscript exist inside the container, and prints the exact `app.ini` stanzas to append. Then restart Forgejo:

```sh
docker compose restart forgejo
```

If the dependency check reports missing tools, either bake them into a derived image (recommended — see [`Dockerfile.example`](Dockerfile.example)) or install them ad-hoc, knowing they vanish when the container is recreated:

```sh
docker exec forgejo apk add --no-cache imagemagick ghostscript
```

## Quick start (bare metal)

```sh
sudo ./install.sh baremetal
sudo systemctl restart forgejo   # after appending the printed app.ini stanzas
```

Full walk-through, verification steps and troubleshooting: **[docs/INSTALL.md](docs/INSTALL.md)**.

## How it works

```
Forgejo file view
   └─ [markup.forgepeek-psd] in app.ini
        └─ pipes file bytes to:  forgepeek render psd
             └─ dispatcher picks handlers/psd (by its header metadata)
                  └─ ImageMagick → PNG → <img src="data:image/png;base64,…">
```

Static formats render as sanitized HTML with a data-URI image. 3D formats use Forgejo's `iframe` render mode: the handler emits a complete, self-contained HTML page (viewer JS inlined, model embedded as base64) that runs in a sandboxed iframe — no CDN, no network fetches, ever.

`forgepeek config` regenerates the `app.ini` stanzas from the installed handlers, so adding a format is: drop in one handler file, re-run `forgepeek config`, append, restart.

- Adding your own format: [docs/ADDING-HANDLERS.md](docs/ADDING-HANDLERS.md)
- Planned formats: [docs/ROADMAP.md](docs/ROADMAP.md)
- Contributing: [CONTRIBUTING.md](CONTRIBUTING.md)

## Security

External renderers execute on the server against user-supplied file content. forgepeek never interpolates file content into commands (data moves only through pipes and temp files), runs Ghostscript with `-dSAFER`, and value-constrains its sanitizer rules. You are still trusting ImageMagick's and Ghostscript's parsers with hostile input — keep them updated. See the security notes in [docs/INSTALL.md](docs/INSTALL.md#security-notes).

## License

[MIT](LICENSE)
