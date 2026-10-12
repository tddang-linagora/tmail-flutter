// Compares layout metrics of the Playwright goldens harness with the ones measured on a device webview.
//   node compare.mjs   (reads playwright-*.json, device-android.log, device-ios.log next to this file)
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const MEDIA = ['maxDeviceWidth480', 'pointerCoarse', 'hoverNone'];
const ANDROID_PROBES = ['sans-serif', 'serif', 'monospace', 'Arial', 'Helvetica', '"Times New Roman"', 'UnknownFont123'];
// Not probed on iOS: UnknownFont123. An iPhone falls back to Times, WebKitGTK to sans-serif, and Playwright cannot change it.
const IOS_PROBES = ['sans-serif', 'serif', 'monospace', 'Arial', 'Helvetica', '"Times New Roman"'];

const browser = Object.fromEntries(
  readdirSync(here)
    .filter((f) => /^playwright-.*\.json$/.test(f))
    .flatMap((f) => JSON.parse(readFileSync(path.join(here, f), 'utf8')))
    .map((r) => [r.case, r.metrics]),
);

const deviceLines = (file) =>
  existsSync(path.join(here, file))
    ? readFileSync(path.join(here, file), 'utf8')
        .split('\n')
        .filter((l) => l.includes('CALIBRATION_JSON '))
        .map((l) => JSON.parse(l.slice(l.indexOf('CALIBRATION_JSON ') + 'CALIBRATION_JSON '.length)))
    : [];

const percent = (a, b) => (Math.abs(a - b) / Math.max(a, b, 1)) * 100;

// A missing value (NaN) counts as a difference.
const farther = (limit) => (x, y) => !(Math.abs(x - y) <= limit);
const percentOver = (limit) => (x, y) => !(percent(x, y) <= limit);
const changed = (x, y) => x !== y;

// [label, browser value, device value, differs]
function checks(android, b, d) {
  const probes = android ? ANDROID_PROBES : IOS_PROBES;
  const tolerance = android ? 1 : 2; // DPR 1 rounds glyph advances; iOS Helvetica is not Arial-metric to the pixel
  return [
    ...MEDIA.map((k) => [k, b[k], d[k], changed]),
    ['contentScrollWidth', b.contentScrollWidth, d.contentScrollWidth, percentOver(5)],
    ['overflowX', b.overflowX, d.overflowX, changed],
    ['scrollHeight', b.scrollHeight, d.scrollHeight, percentOver(android ? 2 : 5)],
    ...probes.map((p) => [`probe ${p}`, b.probes[p], d.probes[p], farther(tolerance)]),
    ...Object.keys(b.heights).map((p) => [`line height ${p}`, b.heights[p], d.heights[p], farther(1)]),
    ...(android ? [['tinyTextHeight', b.tinyTextHeight, d.tinyTextHeight, farther(0.5)]] : []),
  ];
}

function failures(id, b, d) {
  if (d.error) return [`device error: ${d.error}`];
  return checks(id.startsWith('native-android/'), b, d)
    .filter(([, x, y, differs]) => differs(x, y))
    .map(([label, x, y]) => `${label}: browser ${x} / device ${y}`);
}

let failed = 0;
console.log('| case | result | details |\n|---|---|---|');
for (const { case: id, metrics: device } of [...deviceLines('device-android.log'), ...deviceLines('device-ios.log')]) {
  const b = browser[id];
  const out = b ? failures(id, b, device) : ['no browser metrics'];
  failed += out.length ? 1 : 0;
  console.log(`| ${id} | ${out.length ? 'FAIL' : 'ok'} | ${out.join('; ')} |`);
}
console.log(`\n${failed} failing case(s)`);
process.exit(failed ? 1 : 0);
