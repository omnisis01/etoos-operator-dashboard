// @ts-check
const { test, expect } = require('@playwright/test');

// MOCK 모드(키 없음) 기준 — 현재 대시보드(247 운영 OS, 사분면 허브) 회귀 검증.
// 실DB 연결 후에도 이 테스트가 통과해야 회귀가 없음을 보장.

test.describe('로그인', () => {
  test('MOCK 안내 표시 & 로그인 시 대시보드로 이동', async ({ page }) => {
    await page.goto('/app/login.html?mock=1');
    await expect(page.locator('#hint')).toContainText('데모');
    await page.fill('#email', 'director@etoos.com');
    await page.fill('#pw', 'whatever');
    await page.click('button[type="submit"]');
    await expect(page).toHaveURL(/index\.html/);
    await expect(page.locator('#rvStudents')).toContainText('187');
  });
});

test.describe('허브 렌더 (데이터 레이어)', () => {
  test.beforeEach(async ({ page }) => { await page.goto('/app/index.html?mock=1'); });

  test('KPI가 DATA에서 채워짐', async ({ page }) => {
    await expect(page.locator('#rvStudents')).toContainText('187');
    await expect(page.locator('#rvRevenue')).toContainText('1,840');
    await expect(page.locator('#rvUnpaid')).toContainText('412');
    await expect(page.locator('#rvAttend')).toContainText('107/235');
  });

  test('상단 띠 · 4사분면이 렌더됨', async ({ page }) => {
    await expect(page.locator('#band')).toBeVisible();
    for (const k of ['recruit', 'sales', 'operation', 'marketing']) {
      await expect(page.locator(`.qd.${k}`)).toBeVisible();
    }
  });
});

test.describe('세부 진입 & 차트', () => {
  test('매출 세부 → 요약 상단 + 콤보 차트 렌더', async ({ page }) => {
    await page.goto('/app/index.html?mock=1');
    await page.click('.qd.sales');
    await expect(page).toHaveURL(/#sales/);
    await expect(page.locator('#dtBody .panel-title').first()).toHaveText('매출 지표 요약');
    await expect(page.locator('#c1 svg.apexcharts-svg')).toBeVisible();
  });

  test('운영 세부 → 퇴원 사유 분석(상담일지 실데이터)', async ({ page }) => {
    await page.goto('/app/index.html?mock=1');
    await page.click('.qd.operation');
    await expect(page.locator('#dtBody')).toContainText('퇴원 사유 분석');
    await expect(page.locator('.rbar').first()).toContainText('등원 전 환불');
  });
});

test.describe('테마 & 내비게이션', () => {
  test('라이트/다크 토글', async ({ page }) => {
    await page.goto('/app/index.html?mock=1');
    await expect(page.locator('body')).not.toHaveClass(/light/);
    await page.click('.theme-btn');
    await expect(page.locator('body')).toHaveClass(/light/);
    await page.click('.theme-btn');
    await expect(page.locator('body')).not.toHaveClass(/light/);
  });

  test('세부에서 뒤로가기 → 허브 복귀 (로그아웃 안 됨)', async ({ page }) => {
    await page.goto('/app/index.html?mock=1');
    await page.click('.qd.sales');
    await expect(page.locator('#detail')).toBeVisible();
    await page.goBack();
    await expect(page.locator('#hub')).toBeVisible();
    await expect(page).not.toHaveURL(/login/);
  });
});
