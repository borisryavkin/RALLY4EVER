import { defineConfig } from "@playwright/test";
export default defineConfig({
  testDir: "./test/browser",
  workers: 1,
  timeout: 30000,
  use: {
    baseURL: "http://127.0.0.1:57830",
    channel: "chrome",
    viewport: { width: 1440, height: 1100 },
  },
  webServer: {
    command: "npm run dev -- --port 57830",
    url: "http://127.0.0.1:57830",
    reuseExistingServer: true,
  },
  outputDir: "/tmp/r4e-admin-playwright-results",
});
