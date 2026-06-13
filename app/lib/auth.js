// 인증 · 권한 (Supabase Auth)
// MOCK 모드에서는 로그인 없이 '강남구 직영점 원장'으로 동작합니다.

const MOCK_PROFILE = {
  name: "이○○ 원장",
  role: "director",                 // 'director'(원장) | 'exec'(임원)
  branch_id: "11111111-0000-0000-0000-000000000003",
  branch_name: "강남구 직영점",
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
  if (window.USE_MOCK) { location.href = "index.html"; return { error: null }; }
  return sb.auth.signInWithPassword({ email, password });
}

async function signOut() {
  if (!window.USE_MOCK) await sb.auth.signOut();
  location.href = "login.html";
}
