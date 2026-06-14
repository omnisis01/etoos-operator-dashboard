// DB 마이그레이션 실행기 — SQL 파일들을 순서대로 실행
// 사용: PGHOST=... PGPASSWORD=... node scripts/migrate.js db/schema.sql db/seed.sql
// (비밀번호는 환경변수로만 전달 — 파일에 저장하지 않음)
const fs = require('fs');
const { Client } = require('pg');

const files = process.argv.slice(2);

(async () => {
  const client = new Client({
    host: process.env.PGHOST,
    port: +(process.env.PGPORT || 5432),
    user: process.env.PGUSER || 'postgres',
    password: process.env.PGPASSWORD,
    database: process.env.PGDATABASE || 'postgres',
    ssl: { rejectUnauthorized: false },
    connectionTimeoutMillis: 15000,
  });
  await client.connect();
  console.log('✅ DB 접속 성공:', process.env.PGHOST);

  for (const f of files) {
    const sql = fs.readFileSync(f, 'utf8');
    process.stdout.write(`\n▶ 실행: ${f} ... `);
    await client.query(sql);
    process.stdout.write('완료\n');
  }

  const v = await client.query(`select
    (select count(*) from branches) as branches,
    (select count(*) from students) as students,
    (select count(*) from churn_risks) as risks,
    (select count(*) from payments) as payments,
    (select count(*) from metrics_snapshot) as snapshots,
    (select count(*) from action_items) as actions`);
  console.log('\n📊 적재 검증:', v.rows[0]);

  await client.end();
  console.log('🎉 마이그레이션 완료');
})().catch((e) => { console.error('\n❌ 오류:', e.message); process.exit(1); });
