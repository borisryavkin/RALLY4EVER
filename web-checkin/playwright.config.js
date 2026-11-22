import { defineConfig } from "../web-admin/node_modules/@playwright/test/index.mjs";
export default defineConfig({
  testDir: "./test/browser",
  workers: 1,
  use: {
    baseURL: "http://localhost:57832",
    channel: "chrome",
    viewport: { width: 393, height: 852 },
    permissions: ["geolocation"],
    geolocation: { latitude: -33.8926, longitude: 151.2511 },
  },
  webServer: {
    command: "npm run dev",
    url: "http://localhost:57832",
    reuseExistingServer: false,
  },
  outputDir: "/tmp/r4e-anonymous-web-results",
});
