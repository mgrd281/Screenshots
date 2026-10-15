// Browser tests for the website, run against the built pages with the same
// Content Security Policy Vercel sends. See README.md in this folder.
const { defineConfig, devices } = require("@playwright/test");

module.exports = defineConfig({
  testDir: ".",
  fullyParallel: true,
  reporter: "list",
  use: { baseURL: "http://127.0.0.1:4173/" },
  webServer: {
    command: "python3 ../website/build.py && python3 serve.py 4173",
    url: "http://127.0.0.1:4173/",
    reuseExistingServer: false,
  },
  projects: [
    { name: "desktop", use: { ...devices["Desktop Chrome"], viewport: { width: 1440, height: 900 } } },
    { name: "phone", use: { ...devices["Desktop Chrome"], viewport: { width: 390, height: 844 }, hasTouch: true, isMobile: true } },
  ],
});
