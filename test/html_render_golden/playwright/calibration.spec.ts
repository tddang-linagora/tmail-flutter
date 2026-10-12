import { writeFileSync, readFileSync, mkdirSync } from 'node:fs';
import path from 'node:path';
import { test } from './render-fixtures';
import { loadAtFinalSize, readCases } from './render-page';

// Browser side of the device calibration: the same metrics function the device evaluates.
const metricsJs = readFileSync(path.join(__dirname, 'calibration', 'metrics.js'), 'utf8');
const dir = process.env.HTML_RENDER_CALIBRATION_DIR!;
const results: { case: string; metrics: unknown }[] = [];

for (const c of readCases(dir)) {
  test(`calibration ${c.target}/${c.name}`, { tag: `@${c.target}` }, async ({ page }) => {
    await loadAtFinalSize(page, c, dir);
    const metrics = JSON.parse(await page.evaluate(`(${metricsJs})()`));
    results.push({ case: `${c.target}/${c.name}`, metrics });
  });
}

test.afterAll(() => {
  const out = path.join(__dirname, 'calibration');
  mkdirSync(out, { recursive: true });
  writeFileSync(path.join(out, `playwright-${process.pid}.json`), JSON.stringify(results));
});
