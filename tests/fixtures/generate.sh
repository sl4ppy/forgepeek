#!/bin/sh
# Regenerate the committed test fixtures. Dev-time only; needs ImageMagick,
# Ghostscript and python3. Each fixture stays under ~100 KB.
set -eu
cd "$(dirname -- "$0")"

if command -v magick >/dev/null 2>&1; then IM=magick; else IM=convert; fi

echo "== PSD/PSB =="
# Two-layer RGB PSD (ImageMagick writes the flattened composite as frame 0).
$IM -size 64x64 gradient:red-yellow \( -size 32x32 xc:blue \) sample-2layer.psd

# CMYK PSD — exercises the -colorspace sRGB path.
$IM -size 64x64 gradient:green-white -colorspace CMYK sample-cmyk.psd

# Large-canvas PSB (still a small file) — exercises the psb: delegate.
$IM -size 128x128 plasma:fractal -depth 8 sample.psb

# Deterministic corrupt file: right extension, garbage content.
printf 'this is definitely not a photoshop file\n' > corrupt.psd
i=0; while [ $i -lt 64 ]; do printf '\377\376\255\336'; i=$((i+1)); done >> corrupt.psd

echo "== EPS/AI =="
cat > sample.eps <<'EOF'
%!PS-Adobe-3.0 EPSF-3.0
%%BoundingBox: 0 0 100 100
%%EndComments
1 0 0 setrgbcolor
10 10 80 80 rectfill
0 0 1 setrgbcolor
30 30 40 40 rectfill
showpage
%%EOF
EOF
# ".ai" files from modern Illustrator are PDF-compatible; make a tiny PDF.
gs -q -dSAFER -dBATCH -dNOPAUSE -sDEVICE=pdfwrite -o sample.ai sample.eps
printf 'not postscript at all\n' > corrupt.eps

echo "== STL =="
[ -f gen_stl.py ] && python3 gen_stl.py

echo "== FBX =="
[ -f gen_fbx.py ] && python3 gen_fbx.py

echo "== sizes =="
ls -la *.psd *.psb *.eps *.ai *.stl *.fbx 2>/dev/null || true
for f in *.psd *.psb *.eps *.ai *.stl *.fbx; do
    [ -f "$f" ] || continue
    sz=$(wc -c < "$f")
    if [ "$sz" -gt 102400 ]; then
        echo "WARNING: $f is over 100 KB ($sz bytes)" >&2
    fi
done
