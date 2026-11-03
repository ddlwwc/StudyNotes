import { defineConfig, devices } from "@playwright/test";

const port = 8090;
const browserChannel = process.env.CI ? undefined : "chrome";
const channelConfig = browserChannel ? { channel: browserChannel } : {};

export default defineConfig({
  testDir: "./tests/e2e",
  fullyParallel: false,
  workers: 1,
  timeout: 45_000,
  expect: {
    timeout: 8_000
  },
  use: {
    baseURL: `http://127.0.0.1:${port}`,
    trace: "retain-on-failure",
    screenshot: "only-on-failure"
  },
  projects: [
    {
      name: "chromium",
      use: {
        ...devices["Desktop Chrome"],
        ...channelConfig,
        viewport: { width: 1440, height: 1024 }
      }
    },
    {
      name: "mobile-chromium",
      use: {
        ...devices["iPhone 13"],
        browserName: "chromium",
        ...channelConfig
      }
    }
  ],
  webServer: {
    command:
      "STUDYNOTES_REPOSITORY=memory STUDYNOTES_STORAGE=memory PLAYWRIGHT_TEST=1 PUBLISH_REGISTRATION_SECRET=test-registration-secret LIBRARY_MEDIA_KEY_SHA256=sha256:cfe963ab0b485a43d35aa7cba7d5c597bddada296db0444bd2e83ba4bf5c6c6d LIBRARY_MEDIA_CLEANUP_DELAY_SECONDS=0 NEXT_TELEMETRY_DISABLED=1 npm run build && STUDYNOTES_REPOSITORY=memory STUDYNOTES_STORAGE=memory PLAYWRIGHT_TEST=1 PUBLISH_REGISTRATION_SECRET=test-registration-secret LIBRARY_MEDIA_KEY_SHA256=sha256:cfe963ab0b485a43d35aa7cba7d5c597bddada296db0444bd2e83ba4bf5c6c6d LIBRARY_MEDIA_CLEANUP_DELAY_SECONDS=0 NEXT_TELEMETRY_DISABLED=1 npm run start",
    url: `http://127.0.0.1:${port}/api/v1/health`,
    reuseExistingServer: !process.env.CI,
    timeout: 120_000
  }
});
