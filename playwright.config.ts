import { defineConfig } from "@playwright/test";

export default defineConfig({
  testDir: "./tests/e2e",
  fullyParallel: false,
  workers: 1,
  timeout: 120_000,
  expect: {
    timeout: 8_000
  },
  reporter: [["list"]],
  use: {
    channel: "chrome",
    headless: true,
    viewport: { width: 1280, height: 800 },
    trace: "retain-on-failure",
    screenshot: "only-on-failure"
  }
});
