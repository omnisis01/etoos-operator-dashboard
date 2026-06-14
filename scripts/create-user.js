// 로그인 계정 생성 + 프로필을 지점에 매핑 + 실제 로그인 검증
// 사용: PGHOST=.. PGUSER=.. PGPASSWORD=.. SUPABASE_URL=.. ANON_KEY=.. \
//       node scripts/create-user.js <email> <password> <branch_id>
const { Client } = require('pg');

const [email, password, branchId] = process.argv.slice(2);

(async () => {
  const c = new Client({
    host: process.env.PGHOST, port: +(process.env.PGPORT || 5432),
    user: process.env.PGUSER, password: process.env.PGPASSWORD,
    database: 'postgres', ssl: { rejectUnauthorized: false }, connectionTimeoutMillis: 15000,
  });
  await c.connect();

  // 이미 있으면 재사용
  let { rows } = await c.query('select id from auth.users where email=$1', [email]);
  let uid;
  if (rows.length) {
    uid = rows[0].id;
    console.log('• 기존 계정 재사용:', email);
  } else {
    const r = await c.query(`
      insert into auth.users (
        instance_id, id, aud, role, email, encrypted_password,
        email_confirmed_at, created_at, updated_at,
        raw_app_meta_data, raw_user_meta_data,
        confirmation_token, recovery_token, email_change_token_new, email_change
      ) values (
        '00000000-0000-0000-0000-000000000000', gen_random_uuid(),
        'authenticated','authenticated',$1, crypt($2, gen_salt('bf')),
        now(), now(), now(),
        '{"provider":"email","providers":["email"]}', '{"name":"이○○ 원장"}',
        '', '', '', ''
      ) returning id`, [email, password]);
    uid = r.rows[0].id;
    console.log('✅ 계정 생성:', email);
  }

  // identity 멱등 생성 ($1=text uid, user_id 는 ::uuid 캐스팅)
  const idn = await c.query('select 1 from auth.identities where user_id=$1', [uid]);
  if (!idn.rows.length) {
    await c.query(`
      insert into auth.identities (id, provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
      values (gen_random_uuid(), $1::text, $3::uuid, jsonb_build_object('sub',$1::text,'email',$2::text), 'email', now(), now(), now())`, [uid, email, uid]);
    console.log('✅ identity 생성');
  }

  // 트리거가 profiles 자동 생성 → 지점 매핑 + 역할
  await c.query(`update profiles set branch_id=$2, role='director', name='이○○ 원장' where id=$1`, [uid, branchId]);
  const p = await c.query('select name, role, branch_id from profiles where id=$1', [uid]);
  console.log('✅ 프로필 매핑:', p.rows[0]);
  await c.end();

  // 실제 로그인 검증 (anon 키로 토큰 발급 시도)
  const res = await fetch(`${process.env.SUPABASE_URL}/auth/v1/token?grant_type=password`, {
    method: 'POST',
    headers: { 'apikey': process.env.ANON_KEY, 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password }),
  });
  const j = await res.json();
  if (j.access_token) console.log('🎉 로그인 검증 성공 — 토큰 발급됨');
  else console.log('❌ 로그인 검증 실패:', JSON.stringify(j));
})().catch((e) => { console.error('❌ 오류:', e.message); process.exit(1); });
