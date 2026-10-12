// Compares layout metrics of the Playwright goldens harness with the ones measured on a device webview.
//   node compare.mjs   (reads playwright-*.json, device-android.log, device-ios.log next to this file)
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const MEDIA = ['maxDeviceWidth480', 'pointerCoarse', 'hoverNone'];
const ANDROID_PROBES = ['sans-serif', 'serif', 'monospace', 'Arial', 'Helvetica', '"Times New Roman"', 'UnknownFont123'];
const IOS_PROBES = ['Arial', '"Times New Roman"'];

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

function failures(id, b, d) {
  if (d.error) return [`device error: ${d.error}`];
  const out = [];
  const android = id.startsWith('native-android/');
  MEDIA.filter((k) => b[k] !== d[k]).forEach((k) => out.push(`${k}: browser ${b[k]} / device ${d[k]}`));
  if (b.overflowX !== d.overflowX) out.push(`overflowX: browser ${b.overflowX} / device ${d.overflowX}`);
  const limit = android ? 2 : 5;
  if (percent(b.scrollHeight, d.scrollHeight) > limit)
    out.push(`scrollHeight: browser ${b.scrollHeight} / device ${d.scrollHeight} (> ${limit}%)`);
  const probes = android ? ANDROID_PROBES : IOS_PROBES;
  const tolerance = android ? 0.5 : 1;
  probes
    .filter((p) => Math.abs(b.probes[p] - d.probes[p]) > tolerance)
    .forEach((p) => out.push(`probe ${p}: browser ${b.probes[p]} / device ${d.probes[p]}`));
  if (android && Math.abs(b.tinyTextHeight - d.tinyTextHeight) > 0.5)
    out.push(`tinyTextHeight: browser ${b.tinyTextHeight} / device ${d.tinyTextHeight}`);
  return out;
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
