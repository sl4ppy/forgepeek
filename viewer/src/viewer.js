// forgepeek 3D viewer — bundled to lib/viewer.js (IIFE, global ForgePeekViewer)
// and inlined into a fully self-contained HTML page by handlers/stl and
// handlers/fbx. No network access at view time: the model arrives as base64
// inside the page, and any texture URL an FBX references is stubbed out.

import {
  AmbientLight,
  Box3,
  Color,
  DirectionalLight,
  GridHelper,
  HemisphereLight,
  Mesh,
  MeshStandardMaterial,
  PerspectiveCamera,
  Scene,
  Vector3,
  WebGLRenderer,
  LoadingManager,
} from 'three';
import { OrbitControls } from 'three/examples/jsm/controls/OrbitControls.js';
import { STLLoader } from 'three/examples/jsm/loaders/STLLoader.js';
import { FBXLoader } from 'three/examples/jsm/loaders/FBXLoader.js';

const DARK = { bg: 0x161b22, grid: 0x30363d, gridCenter: 0x484f58 };
const LIGHT = { bg: 0xf6f8fa, grid: 0xd0d7de, gridCenter: 0xafb8c1 };

// A 1x1 transparent PNG; substituted for every external texture URL an FBX
// may reference, so nothing ever leaves the sandboxed page.
const BLANK_PIXEL =
  'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';

function isDark() {
  return window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches;
}

function box(root, kind, title, message) {
  const el = document.createElement('div');
  el.className = 'fp-box fp-' + kind;
  const h = document.createElement('p');
  h.className = 'fp-box-title';
  h.textContent = title;
  const p = document.createElement('p');
  p.textContent = message;
  el.appendChild(h);
  el.appendChild(p);
  root.innerHTML = '';
  root.appendChild(el);
}

function decodeBase64(b64) {
  const bin = atob(b64);
  const bytes = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  return bytes.buffer;
}

function countGeometry(object) {
  let triangles = 0;
  let vertices = 0;
  const add = (geom) => {
    const pos = geom.getAttribute('position');
    if (!pos) return;
    vertices += pos.count;
    triangles += geom.index ? geom.index.count / 3 : pos.count / 3;
  };
  if (object.isBufferGeometry) add(object);
  else object.traverse((n) => { if (n.isMesh && n.geometry) add(n.geometry); });
  return { triangles: Math.round(triangles), vertices };
}

function neutralMaterial() {
  return new MeshStandardMaterial({ color: 0x8899aa, metalness: 0.15, roughness: 0.75 });
}

function parseModel(format, buffer) {
  if (format === 'stl') {
    const geometry = new STLLoader().parse(buffer); // binary and ASCII
    geometry.computeVertexNormals();
    return { object: new Mesh(geometry, neutralMaterial()), counts: countGeometry(geometry) };
  }
  if (format === 'fbx') {
    // Stub every URL the loader might resolve (external textures, etc.).
    const manager = new LoadingManager();
    manager.setURLModifier(() => BLANK_PIXEL);
    const group = new FBXLoader(manager).parse(buffer, '');
    // Textures are best-effort: replace unusable materials with a neutral one,
    // and derive normals when the file carries none.
    group.traverse((n) => {
      if (!n.isMesh) return;
      const mats = Array.isArray(n.material) ? n.material : [n.material];
      const broken = mats.some((m) => !m || (m.map && !m.map.image));
      if (!n.material || broken) n.material = neutralMaterial();
      if (n.geometry && !n.geometry.getAttribute('normal')) {
        n.geometry.computeVertexNormals();
      }
    });
    return { object: group, counts: countGeometry(group) };
  }
  throw new Error('unsupported format: ' + format);
}

function fitCameraTo(object, camera, controls) {
  const bounds = new Box3().setFromObject(object);
  const center = bounds.getCenter(new Vector3());
  const size = bounds.getSize(new Vector3());
  const maxDim = Math.max(size.x, size.y, size.z) || 1;
  const dist = (maxDim / (2 * Math.tan((camera.fov * Math.PI) / 360))) * 1.5;
  camera.position.set(center.x + dist * 0.7, center.y + dist * 0.6, center.z + dist * 0.8);
  camera.near = dist / 100;
  camera.far = dist * 100;
  camera.updateProjectionMatrix();
  controls.target.copy(center);
  controls.update();
  return { bounds, center, maxDim };
}

const state = { root: null, opts: null, dispose: null, byteLength: -1, failed: false };

export function init(opts) {
  const root = document.getElementById(opts.rootId || 'forgepeek');
  if (!root) return;
  state.root = root;
  state.opts = opts;

  // The parent page (forgepeek's footer shim) may post the file's pristine
  // bytes: Forgejo's standalone render route pipes binary input through a
  // UTF-8 converter, corrupting it, so the shim fetches the raw file and
  // hands it over. Re-render only when the embedded copy failed or the
  // sizes disagree (i.e. the embedded bytes really were mangled).
  window.addEventListener('message', (ev) => {
    if (ev.source !== window.parent) return;
    const raw = ev.data && ev.data.forgepeekRaw;
    if (!(raw instanceof ArrayBuffer)) return;
    if (state.opts.tooLarge) return;
    if (!state.failed && raw.byteLength === state.byteLength) return;
    boot(raw);
  });

  if (opts.tooLarge) {
    box(root, 'notice',
      'File too large to preview (' + opts.tooLarge.sizeMB + ' MB)',
      'The 3D preview limit is ' + opts.tooLarge.limitMB +
      ' MB (FORGEPEEK_MAX_BYTES_3D). Download the file to view it.');
    signalReady({ tooLarge: true });
    return;
  }

  let buffer;
  try {
    buffer = decodeBase64(opts.data || '');
  } catch (err) {
    buffer = new ArrayBuffer(0);
  }
  boot(buffer);
}

function boot(buffer) {
  const root = state.root;
  const opts = state.opts;
  if (state.dispose) {
    state.dispose();
    state.dispose = null;
  }
  state.byteLength = buffer.byteLength;

  let parsed;
  try {
    parsed = parseModel(opts.format, buffer);
    if (!parsed.counts.vertices) throw new Error('no geometry found in file');
  } catch (err) {
    state.failed = true;
    box(root, 'error',
      'forgepeek: could not display this ' + String(opts.format || '').toUpperCase() + ' file',
      'The model failed to parse: ' + (err && err.message ? err.message : err));
    signalReady({ error: true });
    return;
  }
  state.failed = false;

  const theme = isDark() ? DARK : LIGHT;
  const scene = new Scene();
  scene.background = new Color(theme.bg);
  scene.add(parsed.object);

  const camera = new PerspectiveCamera(50, 1, 0.1, 1000);
  const renderer = new WebGLRenderer({ antialias: true });
  renderer.setPixelRatio(window.devicePixelRatio || 1);
  root.innerHTML = '';
  root.appendChild(renderer.domElement);

  const controls = new OrbitControls(camera, renderer.domElement);
  controls.enableDamping = true;
  controls.dampingFactor = 0.1;

  const fit = fitCameraTo(parsed.object, camera, controls);

  scene.add(new HemisphereLight(0xffffff, 0x445566, 1.2));
  const sun = new DirectionalLight(0xffffff, 1.6);
  sun.position.set(fit.center.x + fit.maxDim, fit.center.y + fit.maxDim * 2, fit.center.z + fit.maxDim);
  scene.add(sun);
  scene.add(new AmbientLight(0xffffff, 0.25));

  const grid = new GridHelper(fit.maxDim * 4, 20, theme.gridCenter, theme.grid);
  grid.position.y = fit.bounds.min.y;
  grid.position.x = fit.center.x;
  grid.position.z = fit.center.z;
  scene.add(grid);

  // --- overlay UI -----------------------------------------------------------
  const hud = document.createElement('div');
  hud.className = 'fp-hud';
  const stats = document.createElement('span');
  stats.id = 'fp-stats';
  stats.textContent =
    parsed.counts.triangles.toLocaleString() + ' triangles · ' +
    parsed.counts.vertices.toLocaleString() + ' vertices';
  const wire = document.createElement('button');
  wire.id = 'fp-wireframe';
  wire.type = 'button';
  wire.textContent = 'wireframe';
  let wireOn = false;
  wire.addEventListener('click', () => {
    wireOn = !wireOn;
    wire.classList.toggle('fp-on', wireOn);
    parsed.object.traverse
      ? parsed.object.traverse((n) => {
          if (!n.isMesh) return;
          (Array.isArray(n.material) ? n.material : [n.material]).forEach((m) => {
            if (m) m.wireframe = wireOn;
          });
        })
      : null;
  });
  const reset = document.createElement('button');
  reset.type = 'button';
  reset.textContent = 'reset view';
  reset.addEventListener('click', () => fitCameraTo(parsed.object, camera, controls));
  hud.appendChild(stats);
  hud.appendChild(wire);
  hud.appendChild(reset);
  root.appendChild(hud);

  function resize() {
    const w = root.clientWidth || 300;
    const h = root.clientHeight || 300;
    camera.aspect = w / h;
    camera.updateProjectionMatrix();
    renderer.setSize(w, h, false);
    renderer.domElement.style.width = '100%';
    renderer.domElement.style.height = '100%';
  }
  window.addEventListener('resize', resize);
  resize();

  renderer.setAnimationLoop(() => {
    controls.update();
    renderer.render(scene, camera);
  });

  state.dispose = () => {
    renderer.setAnimationLoop(null);
    window.removeEventListener('resize', resize);
    controls.dispose();
    renderer.dispose();
    root.innerHTML = '';
  };

  signalReady({ triangles: parsed.counts.triangles, vertices: parsed.counts.vertices });
}

function signalReady(state) {
  // Consumed by the headless smoke test; harmless in production.
  window.__forgepeekReady = state;
}
