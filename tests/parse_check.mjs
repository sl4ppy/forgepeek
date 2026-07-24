// Node-level loader check: prove the pinned three.js loaders parse the
// committed fixtures (and reject the corrupt ones) without needing a
// browser. Run from repo root: node tests/parse_check.mjs
// Requires viewer/node_modules (sh viewer/build.sh installs it).
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const fixtures = join(root, 'tests', 'fixtures');
const mods = join(root, 'viewer', 'node_modules');

const { STLLoader } = await import(join(mods, 'three/examples/jsm/loaders/STLLoader.js'));
const { FBXLoader } = await import(join(mods, 'three/examples/jsm/loaders/FBXLoader.js'));

let failed = 0;
const ok = (name, cond, detail = '') => {
  if (cond) console.log(`ok   ${name}${detail ? ' (' + detail + ')' : ''}`);
  else { console.error(`FAIL ${name} ${detail}`); failed = 1; }
};
const buf = (f) => {
  const b = readFileSync(join(fixtures, f));
  return b.buffer.slice(b.byteOffset, b.byteOffset + b.byteLength);
};

// STL binary
{
  const g = new STLLoader().parse(buf('cube-binary.stl'));
  ok('stl_binary_cube', g.getAttribute('position')?.count === 36, '12 triangles');
}
// STL ASCII
{
  const g = new STLLoader().parse(buf('tetra-ascii.stl'));
  ok('stl_ascii_tetra', g.getAttribute('position')?.count === 12, '4 triangles');
}
// STL corrupt must throw or yield no geometry
{
  let threw = false, count = -1;
  try { count = new STLLoader().parse(buf('corrupt.stl')).getAttribute('position')?.count ?? 0; }
  catch { threw = true; }
  ok('stl_corrupt_rejected', threw || count === 0, threw ? 'threw' : `count=${count}`);
}
// FBX ASCII cube
{
  const group = new FBXLoader().parse(buf('cube-ascii.fbx'), '');
  let verts = 0;
  group.traverse((n) => { if (n.isMesh) verts += n.geometry.getAttribute('position').count; });
  ok('fbx_ascii_cube', verts === 36, `${verts} vertices after triangulation`);
}
// FBX corrupt must throw
{
  let threw = false;
  try { new FBXLoader().parse(buf('corrupt.fbx'), ''); } catch { threw = true; }
  ok('fbx_corrupt_rejected', threw);
}

process.exit(failed);
