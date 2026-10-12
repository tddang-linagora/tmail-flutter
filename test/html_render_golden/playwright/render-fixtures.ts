import { test as base, chromium, type BrowserContext } from '@playwright/test';
import { mkdirSync, mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';

// flutter_inappwebview on Android: minimumFontSize = minimumLogicalFontSize = 8.
// Only a Chromium profile can set them, so the native-android project runs in one.
const androidPrefs = { webkit: { webprefs: { minimum_font_size: 8, minimum_logical_font_size: 8 } } };

export const test = base.extend<{}, { androidContext: BrowserContext | undefined }>({
  androidContext: [
    async ({}, use, workerInfo) => {
      if (workerInfo.project.name !== 'native-android') return use(undefined);
      const dir = mkdtempSync(path.join(tmpdir(), 'android-profile-'));
      mkdirSync(path.join(dir, 'Default'));
      writeFileSync(path.join(dir, 'Default', 'Preferences'), JSON.stringify(androidPrefs));
      const u = workerInfo.project.use;
      const context = await chromium.launchPersistentContext(dir, {
        channel: 'chromium',
        headless: true,
        isMobile: true,
        hasTouch: true,
        colorScheme: 'light',
        deviceScaleFactor: u.deviceScaleFactor,
        screen: u.screen,
        viewport: { width: 390, height: 800 },
        env: u.launchOptions?.env,
      });
      await use(context);
      await context.close();
    },
    { scope: 'worker' },
  ],
  page: async ({ page, androidContext }, use) => {
    if (!androidContext) return use(page);
    const androidPage = await androidContext.newPage();
    await use(androidPage);
    await androidPage.close();
  },
});

export { expect } from '@playwright/test';
