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
      "STUDYNOTES_REPOSITORY=memory STUDYNOTES_STORAGE=memory PLAYWRIGHT_TEST=1 PUBLISH_REGISTRATION_SECRET=test-registration-secret NEXT_TELEMETRY_DISABLED=1 npm run build && STUDYNOTES_REPOSITORY=memory STUDYNOTES_STORAGE=memory PLAYWRIGHT_TEST=1 PUBLISH_REGISTRATION_SECRET=test-registration-secret NEXT_TELEMETRY_DISABLED=1 npm run start",
    url: `http://127.0.0.1:${port}/api/v1/health`,
    reuseExistingServer: !process.env.CI,
    timeout: 120_000
  }
});
