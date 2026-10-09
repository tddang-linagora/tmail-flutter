import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
  testDir: '.',
  testMatch: 'render.spec.ts',
  snapshotPathTemplate: '{testDir}/goldens/{arg}{ext}',
  fullyParallel: true,
  reporter: [['list'], ['html', { open: 'never' }]],
  expect: {
    toHaveScreenshot: { animations: 'disabled', caret: 'hide', maxDiffPixelRatio: 0 },
  },
  projects: [
    { name: 'chromium', grep: /@chromium/, use: { ...devices['Desktop Chrome'], deviceScaleFactor: 1 } },
    { name: 'webkit', grep: /@webkit/, use: { ...devices['Desktop Safari'], deviceScaleFactor: 1 } },
  ],
});
