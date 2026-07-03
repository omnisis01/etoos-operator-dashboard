// 인증 · 권한 (Supabase Auth)
// MOCK 모드 = 데모 시연용. 실 지점/원장 정보 없이 'TEST점 원장'으로 동작.

// ── 계정 층위 (db/roles.sql과 동일 구조) ─────────────────────────
//  (1) exec 대표·임원 = (2) hq_staff 본사 담당  >  (3) director 지점 원장  >  (4) staff 지점 직원
//  · allBranches: 전사(모든 지점) 조회 — exec·hq_staff 동급
//  · sales:       매출·미수금 열람 — staff만 차단
//  · manage:      계정 발급·전사 설정 — exec 전용
const ROLES = {
  exec:     { rank: 4, label: "임원", allBranches: true,  sales: true,  manage: true  },
  hq_staff: { rank: 3, label: "본사", allBranches: true,  sales: true,  manage: false },
  director: { rank: 2, label: "원장", allBranches: false, sales: true,  manage: false },
  staff:    { rank: 1, label: "직원", allBranches: false, sales: false, manage: false },
};
function roleInfo(role)     { return ROLES[role] || ROLES.staff; }   // 미지정 role은 최소권한
function can(profile, perm) { return !!roleInfo(profile?.role)[perm]; }

const MOCK_PROFILE = {
  name: "데모 원장",
  role: "director",                 // 'exec' | 'hq_staff' | 'director' | 'staff'
  branch_id: "11111111-0000-0000-0000-000000000003",
  branch_name: "TEST점",
};

async function currentProfile() {
  if (window.USE_MOCK) return MOCK_PROFILE;
  const { data: { user } } = await sb.auth.getUser();
  if (!user) return null;
  const { data } = await sb
    .from("profiles")
    .select("name, role, branch_id, branches(name)")
    .eq("id", user.id)
    .single();
  if (!data) return null;
  return { ...data, branch_name: data.branches?.name ?? "전사" };
}

// 대시보드 진입 가드 — 비로그인 시 로그인 화면으로
async function requireAuth() {
  if (window.USE_MOCK) return MOCK_PROFILE;     // 프로토타입: 로그인 우회
  const { data: { session } } = await sb.auth.getSession();
  if (!session) { location.href = "login.html"; return null; }
  return currentProfile();
}

async function signIn(email, password) {
  if (window.USE_MOCK) return { error: null };   // 이동은 호출부(login.html)에서
  return sb.auth.signInWithPassword({ email, password });
}

async function signOut() {
  if (!window.USE_MOCK) await sb.auth.signOut();
  location.href = "login.html";
}
