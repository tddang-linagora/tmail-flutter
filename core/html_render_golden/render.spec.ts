import { test, expect } from '@playwright/test';
import { existsSync, readFileSync } from 'node:fs';
import path from 'node:path';

type RenderCase = { name: string; target: string; engine: string; width: number };

const exportDir = process.env.HTML_RENDER_EXPORT_DIR ?? path.resolve(__dirname, '.export');
const cases: RenderCase[] = JSON.parse(readFileSync(path.join(exportDir, 'cases.json'), 'utf8'));

const svg = (w: number, h: number) =>
  `<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}"><rect width="100%" height="100%" fill="#c8c8c8"/></svg>`;
const PLACEHOLDER = /^https:\/\/fixture\.invalid\/(?:img|cid|est)\/(\d+)x(\d+)/;
const MAX_HEIGHT = 20000;

for (const c of cases) {
  test(`${c.target}/${c.name}`, { tag: `@${c.engine}` }, async ({ page }) => {
    // Offline: only the local page + fonts are served; images are gray SVGs.
    await page.route('**/*', (route) => {
      const url = route.request().url();
      if (url.startsWith('http://render.test/')) {
        const file = path.join(exportDir, decodeURIComponent(new URL(url).pathname));
        return existsSync(file) ? route.fulfill({ path: file }) : route.abort();
      }
      const m = PLACEHOLDER.exec(url);
      if (m) return route.fulfill({ contentType: 'image/svg+xml', body: svg(+m[1], +m[2]) });
      if (route.request().resourceType() === 'image')
        return route.fulfill({ contentType: 'image/svg+xml', body: svg(600, 300) });
      return route.abort();
    });
    // Lazy images start loading before `load`, so the viewer's first layout pass
    // already sees every image size; later image loads would re-run it at random times.
    await page.addInitScript(() => {
      document.addEventListener('DOMContentLoaded', () => {
        document.querySelectorAll('img[loading="lazy"]').forEach((i) => i.setAttribute('loading', 'eager'));
      });
    });
    const url = `http://render.test/${c.target}/${c.name}.html`;
    const settle = () =>
      page.evaluate(async () => {
        await document.fonts.ready;
        await Promise.all([...document.images].map((i) => i.decode().catch(() => {})));
        await new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r)));
      });
    const contentHeight = () => page.evaluate(() => Math.ceil(document.body.getBoundingClientRect().bottom));

    // Measure at a first size, then load again in a viewport taller than the content:
    // resizing a loaded page would re-run the viewer's responsive layout (scrollbar
    // width changes), and a reload lays out once, at the final size.
    await page.setViewportSize({ width: c.width, height: 800 });
    await page.goto(url, { waitUntil: 'load' });
    await settle();
    const measured = await contentHeight();
    await page.setViewportSize({ width: c.width, height: Math.min(measured + 400, MAX_HEIGHT) });
    await page.reload({ waitUntil: 'load' });
    await settle();
    const full = await contentHeight();
    if (full > MAX_HEIGHT)
      test.info().annotations.push({ type: 'truncated', description: `${full}px, compared up to ${MAX_HEIGHT}px` });
    const height = Math.min(Math.max(full, 200), MAX_HEIGHT);
    await expect(page).toHaveScreenshot(`${c.target}/${c.name}.png`, {
      clip: { x: 0, y: 0, width: c.width, height },
    });
  });
}
