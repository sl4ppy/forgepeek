# Roadmap

Planned handlers, roughly in order of expected demand. Contributions welcome — see [ADDING-HANDLERS.md](ADDING-HANDLERS.md).

| Format | Extensions | Likely toolchain | Mode |
|---|---|---|---|
| GIMP | `.xcf` | ImageMagick (`xcf:` coder reads flattened) or `xcf2png` | sanitized |
| Camera RAW | `.cr2` `.nef` `.arw` `.dng` | `dcraw_emu`/`libraw` to extract the embedded JPEG preview (fast), ImageMagick fallback | sanitized |
| OBJ | `.obj` (+`.mtl` best-effort) | existing three.js viewer + OBJLoader (extend the bundle) | iframe |
| glTF | `.glb` `.gltf` | existing viewer + GLTFLoader; `.glb` self-contained, `.gltf` external buffers best-effort | iframe |
| 3MF | `.3mf` | existing viewer + ThreeMFLoader (needs zip support via fflate, already bundled) | iframe |
| KiCad | `.kicad_pcb` `.kicad_sch` | `kicad-cli export svg` (headless) — heavyweight container dependency | sanitized |
| Layered TIFF | `.tif` `.tiff` (multi-page/layered) | ImageMagick `[0]`/`-flatten`, same pattern as PSD | sanitized |
| DICOM | `.dcm` | `dcmj2pnm` (dcmtk) or GDCM; window/level defaults are the hard part | sanitized |
| 3ds Max | `.max` | Embedded-thumbnail only (format is proprietary — no parser/converter exists): OLE compound file, SummaryInformation property 17 DIB → ImageMagick. Needs python3 (stdlib OLE parse, ~120 lines) | sanitized |
| Blender | `.blend` | Embedded-thumbnail only (no JS loader; headless Blender too heavy for the container): `TEST` block raw RGBA → ImageMagick. Needs python3 + zstd CLI (modern .blend are zstd-compressed) | sanitized |

Viewer improvements under consideration: FBX animation playback (clips exist in the loaded data), measurement overlay for STL (print-bed sanity checks), and optional server-side mesh decimation for very large models.
