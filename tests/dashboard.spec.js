// @ts-check
const { test, expect } = require('@playwright/test');

// MOCK 모드(키 없음) 기준 — 로그인·역할·렌더·테마 흐름 검증.
// 실DB 연결 후에도 이 테스트가 통과해야 회귀가 없음을 보장.

test.describe('로그인', () => {
  test('MOCK 안내 표시 & 로그인 시 대시보드로 이동', async ({ page }) => {
    await page.goto('/app/login.html?mock=1');
    await expect(page.locator('#hint')).toContainText('MOCK');
    await page.fill('#email', 'director@etoos.com');
    await page.fill('#pw', 'whatever');
    await page.click('button[type="submit"]');
    await expect(page).toHaveURL(/index\.html/);
    await expect(page.locator('#kpiStudents')).toHaveText('187');
  });
});

test.describe('대시보드 렌더 (데이터 레이어)', () => {
  test.beforeEach(async ({ page }) => { await page.goto('/app/index.html?mock=1'); });

  test('KPI가 DATA에서 채워짐', async ({ page }) => {
    await expect(page.locator('#kpiRevenue')).toHaveText('1,840');
    await expect(page.locator('#kpiStudents')).toHaveText('187');
    await expect(page.locator('#kpiUnpaid')).toHaveText('412만원');
    await expect(page.locator('#kpiAttend')).toHaveText('88%');
  });

  test('명단·액션이 DATA에서 렌더됨', async ({ page }) => {
    await expect(page.locator('#riskList .row')).toHaveCount(5);
    await expect(page.locator('#payList .row')).toHaveCount(4);
    await expect(page.locator('#planBody .plan-grp')).toHaveCount(3);
    await expect(page.locator('#riskList .row').first()).toContainText('홍○○');
  });

  test('차트(라인·도넛·바)가 렌더됨', async ({ page }) => {
    await expect(page.locator('#lineBranch svg.apexcharts-svg')).toBeVisible();
    await expect(page.locator('#donutReason svg.apexcharts-svg')).toBeVisible();
    await expect(page.locator('#barBranch svg.apexcharts-svg')).toBeVisible();
  });

  test('도넛이 범례를 침범하지 않음(겹침 회귀 방지)', async ({ page }) => {
    const donut = await page.locator('#donutReason').boundingBox();
    const legend = await page.locator('#donutReason ~ .donut-legend, .donut-wrap:has(#donutReason) .donut-legend').boundingBox();
    expect(donut.x + donut.width).toBeLessThanOrEqual(legend.x + 1);
  });
});

test.describe('테마 & 역할', () => {
  test('라이트/다크 토글', async ({ page }) => {
    await page.goto('/app/index.html?mock=1');
    await expect(page.locator('body')).not.toHaveClass(/light/);
    await page.click('#themeBtn');
    await expect(page.locator('body')).toHaveClass(/light/);
    await page.click('#themeBtn');
    await expect(page.locator('body')).not.toHaveClass(/light/);
  });

  test('원장(director)은 전사 토글이 숨겨짐', async ({ page }) => {
    await page.goto('/app/index.html?mock=1');
    await expect(page.locator('#btnHQ')).toBeHidden();
  });
});
