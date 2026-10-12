import type { Page } from '@playwright/test';
import { existsSync, readFileSync } from 'node:fs';
import path from 'node:path';

export type RenderCase = { name: string; target: string; engine: string; width: number; maxHeight: number };

export const exportDir = process.env.HTML_RENDER_EXPORT_DIR ?? path.resolve(__dirname, '.export');

export const readCases = (dir = exportDir): RenderCase[] =>
  JSON.parse(readFileSync(path.join(dir, 'cases.json'), 'utf8'));

const svg = (w: number, h: number) =>
  `<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}"><rect width="100%" height="100%" fill="#c8c8c8"/></svg>`;
const PLACEHOLDER = /^https:\/\/fixture\.invalid\/(?:img|cid|est)\/(\d+)x(\d+)/;

// flutter_inappwebview HtmlContentViewer (supportZoom: false) appends this meta on iOS at document end.
const iosNoZoomMeta = () =>
  document.addEventListener('DOMContentLoaded', () => {
    const meta = document.createElement('meta');
    meta.name = 'viewport';
    meta.content = 'width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no';
    document.head.appendChild(meta);
  });

// Android WebView as measured on a Pixel emulator (see calibrate.sh): standard/sans = Roboto,
// serif = Noto Serif, fixed = a 0.6em-advance monospace (Liberation Mono has the same advances).
export async function emulateWebViewDefaults(page: Page, target: string) {
  if (target === 'native-ios') await page.addInitScript(iosNoZoomMeta);
  if (target !== 'native-android') return;
  const cdp = await page.context().newCDPSession(page);
  await cdp.send('Page.setFontFamilies', {
    fontFamilies: { standard: 'Roboto', sansSerif: 'Roboto', serif: 'Noto Serif', fixed: 'Liberation Mono' },
  });
  await cdp.send('Page.setFontSizes', { fontSizes: { standard: 16, fixed: 16 } });
}

/** Offline: only the local page + fonts are served; images are gray SVGs. */
async function routeOffline(page: Page, dir: string) {
  await page.route('**/*', (route) => {
    const url = route.request().url();
    if (url.startsWith('http://render.test/')) {
      const file = path.join(dir, decodeURIComponent(new URL(url).pathname));
      return existsSync(file) ? route.fulfill({ path: file }) : route.abort();
    }
    const m = PLACEHOLDER.exec(url);
    if (m) return route.fulfill({ contentType: 'image/svg+xml', body: svg(+m[1], +m[2]) });
    if (route.request().resourceType() === 'image') return route.fulfill({ contentType: 'image/svg+xml', body: svg(600, 300) });
    return route.abort();
  });
}

// Lazy images start loading before `load`, so the viewer's first layout pass
// already sees every image size; later image loads would re-run it at random times.
const forceEagerImages = () =>
  document.addEventListener('DOMContentLoaded', () => {
    document.querySelectorAll('img[loading="lazy"]').forEach((i) => i.setAttribute('loading', 'eager'));
  });

const settle = (page: Page) =>
  page.evaluate(async () => {
    await document.fonts.ready;
    await Promise.all([...document.images].map((i) => i.decode().catch(() => {})));
    await new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r)));
  });

const contentHeight = (page: Page) => page.evaluate(() => Math.ceil(document.body.getBoundingClientRect().bottom));

/**
 * Measures at a first size, then loads again in a viewport taller than the content:
 * resizing a loaded page would re-run the viewer's responsive layout (scrollbar
 * width changes), and a reload lays out once, at the final size. Returns the content height.
 */
export async function loadAtFinalSize(page: Page, c: RenderCase, dir = exportDir): Promise<number> {
  await routeOffline(page, dir);
  await page.addInitScript(forceEagerImages);
  await emulateWebViewDefaults(page, c.target);
  const url = `http://render.test/${c.target}/${c.name}.html`;
  await page.setViewportSize({ width: c.width, height: 800 });
  await page.goto(url, { waitUntil: 'load' });
  await settle(page);
  const measured = await contentHeight(page);
  await page.setViewportSize({ width: c.width, height: Math.min(measured + 400, c.maxHeight) });
  await page.reload({ waitUntil: 'load' });
  await settle(page);
  return contentHeight(page);
}
