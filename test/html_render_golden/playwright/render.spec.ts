import { test, expect } from './render-fixtures';
import { loadAtFinalSize, readCases } from './render-page';

for (const c of readCases()) {
  test(`${c.target}/${c.name}`, { tag: `@${c.target}` }, async ({ page }) => {
    const full = await loadAtFinalSize(page, c);
    if (full > c.maxHeight)
      test.info().annotations.push({ type: 'truncated', description: `${full}px, compared up to ${c.maxHeight}px` });
    const height = Math.min(Math.max(full, 200), c.maxHeight);
    await expect(page).toHaveScreenshot(`${c.target}/${c.name}.png`, {
      clip: { x: 0, y: 0, width: c.width, height },
    });
  });
}
