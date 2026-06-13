// @ts-check
const { defineConfig, devices } = require('@playwright/test');

module.exports = defineConfig({
  testDir: './tests',
  fullyParallel: true,
  reporter: 'list',
  timeout: 30000,
  use: {
    baseURL: 'http://localhost:8931',
    trace: 'on-first-retry',
  },
  projects: [
    { name: 'chromium', use: { ...devices['Desktop Chrome'] } },
  ],
  // 정적 서버 — 이미 8931에 떠 있으면 재사용
  webServer: {
    command: 'python3 -m http.server 8931',
    url: 'http://localhost:8931/app/login.html',
    reuseExistingServer: true,
    timeout: 20000,
  },
});
