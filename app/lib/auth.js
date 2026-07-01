// 인증 · 권한 (Supabase Auth)
// MOCK 모드 = 데모 시연용. 실 지점/원장 정보 없이 'TEST점 원장'으로 동작.

const MOCK_PROFILE = {
  name: "데모 원장",
  role: "director",                 // 'director'(원장) | 'exec'(임원)
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
