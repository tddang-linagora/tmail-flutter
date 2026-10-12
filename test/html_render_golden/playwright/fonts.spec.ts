import { test, expect } from './render-fixtures';
import { emulateWebViewDefaults } from './render-page';

// Gate for the font setup: a requested family must lay out exactly like the family
// the real webview resolves it to. A failure means the fontconfig is wrong.
const ios: [string, string][] = [
  ['Helvetica', '"Liberation Sans"'],
  ['Arial', '"Liberation Sans"'],
  ['sans-serif', '"Liberation Sans"'],
  ['-apple-system', '"Liberation Sans"'],
  ['"Helvetica Neue"', '"Liberation Sans"'],
  ['serif', '"Liberation Serif"'],
  ['Times', '"Liberation Serif"'],
  ['monospace', '"Liberation Mono"'],
  ['"Courier New"', '"Liberation Mono"'],
];
const expected: Record<string, [string, string][]> = {
  'native-android': [
    ['Arial', 'Roboto'],
    ['Helvetica', 'Roboto'],
    ['sans-serif', 'Roboto'],
    ['serif', '"Noto Serif"'],
    ['UnknownFont123', 'Roboto'],
    ['"Times New Roman"', '"Noto Serif"'],
    ['monospace', '"Liberation Mono"'],
  ],
  'native-ios': ios,
  'ios-previewer': ios,
};

for (const [target, pairs] of Object.entries(expected)) {
  test(`font map ${target}`, { tag: `@${target}` }, async ({ page }) => {
    await emulateWebViewDefaults(page, target);
    await page.setContent('<!doctype html><body></body>');
    const textSize = (font: string, size = 16) =>
      page.evaluate(
        ([f, px]) => {
          const s = document.createElement('span');
          s.style.cssText = `position:absolute;white-space:nowrap;font-size:${px}px;font-family:${f}`;
          s.textContent = 'Hamburgefonstiv 0123456789 Ếọ Жд';
          document.body.appendChild(s);
          const box = s.getBoundingClientRect();
          s.remove();
          return { width: box.width, height: box.height };
        },
        [font, size] as const,
      );
    for (const [requested, real] of pairs)
      expect((await textSize(requested)).width, `${requested} -> ${real}`).toBe((await textSize(real)).width);
    expect((await textSize('sans-serif')).width).not.toBe((await textSize('monospace')).width);
    // Android WebView: minimumFontSize 8 keeps 4px text from collapsing.
    if (target === 'native-android') expect((await textSize('sans-serif', 4)).height).toBeGreaterThanOrEqual(8);
  });
}
