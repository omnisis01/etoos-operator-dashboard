// Supabase 클라이언트 초기화
// (HTML 에서 @supabase/supabase-js CDN 로드 후 이 파일을 불러옵니다)
(function () {
  const c = window.APP_CONFIG || {};
  // 테스트/미리보기용: URL 에 ?mock=1 이면 강제로 샘플 데이터
  const forceMock = new URLSearchParams(location.search).get('mock') === '1';
  window.USE_MOCK = forceMock || !(c.USE_SUPABASE && c.SUPABASE_URL && c.SUPABASE_ANON_KEY);
  window.sb = window.USE_MOCK
    ? null
    : window.supabase.createClient(c.SUPABASE_URL, c.SUPABASE_ANON_KEY);
  if (window.USE_MOCK) {
    console.info("[운영 대시보드] MOCK 모드 — config.js 에 Supabase 키를 넣으면 실제 DB로 전환됩니다.");
  }
})();
