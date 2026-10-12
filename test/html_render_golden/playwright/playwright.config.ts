import { defineConfig, devices } from '@playwright/test';
import path from 'node:path';

const env = (name: string) =>
  ({ ...process.env, FONTCONFIG_FILE: path.resolve(__dirname, 'fontconfig', `${name}.conf`) }) as Record<string, string>;

// Phone webview: 390 CSS px wide, so `device-width`, `max-device-width` and pointer queries answer as on a phone.
const phone = {
  isMobile: true,
  hasTouch: true,
  deviceScaleFactor: 1,
  screen: { width: 390, height: 844 },
  colorScheme: 'light' as const,
};

export default defineConfig({
  testDir: '.',
  testMatch: process.env.HTML_RENDER_CALIBRATION ? 'calibration.spec.ts' : ['render.spec.ts', 'fonts.spec.ts'],
  snapshotPathTemplate: '{testDir}/goldens/{arg}{ext}',
  // Browser start-up is slow under amd64 emulation (Apple Silicon); pixels stay exact.
  timeout: 120_000,
  fullyParallel: true,
  reporter: [['list'], ['html', { open: 'never' }]],
  expect: {
    toHaveScreenshot: { animations: 'disabled', caret: 'hide', maxDiffPixelRatio: 0 },
  },
  projects: [
    {
      name: 'native-android',
      grep: /@native-android\b/,
      use: { browserName: 'chromium', ...phone, launchOptions: { env: env('android') } },
    },
    {
      name: 'native-ios',
      grep: /@native-ios\b/,
      use: { browserName: 'webkit', ...phone, launchOptions: { env: env('ios') } },
    },
    {
      name: 'ios-previewer',
      grep: /@ios-previewer\b/,
      use: { browserName: 'webkit', ...phone, launchOptions: { env: env('ios') } },
    },
    { name: 'web', grep: /@web\b/, use: { ...devices['Desktop Chrome'], deviceScaleFactor: 1 } },
  ],
});
