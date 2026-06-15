// ERP 미납(미수금) 엑셀 → branch_unpaid 적재 + metrics_snapshot 갱신
// 사용: PGHOST=.. PGUSER=.. PGPASSWORD=.. node scripts/ingest-unpaid.js <branchId> <file1.xls> ...
const XLSX = require('xlsx');
const { Client } = require('pg');

const [branchId, ...files] = process.argv.slice(2);

function parse(file, seen) {
  const wb = XLSX.readFile(file, { codepage: 949 });
  const rows = XLSX.utils.sheet_to_json(wb.Sheets[wb.SheetNames[0]], { header: 1, defval: '' });
  // 머리글 row index 2, 데이터 row 3+
  for (let i = 3; i < rows.length; i++) {
    const r = rows[i];
    const name = String(r[1] || '').trim();
    if (!name) continue;
    if (String(r[8] || '').trim() !== '미납') continue;
    const billed = Number(r[14]) || 0, paid = Number(r[15]) || 0;
    let bal = Number(r[16]); if (!bal) bal = billed - paid;
    const oid = r[17] || `${name}|${r[6]}|${billed}|${r[9]}`;
    const due = String(r[9] || '').trim();
    seen.set(oid, { name, phone: String(r[2] || '').trim(), bal, due });
  }
}

(async () => {
  const seen = new Map();
  for (const f of files) parse(f, seen);
  // 학생별 집계
  const agg = new Map();
  for (const v of seen.values()) {
    const k = v.name + '|' + v.phone;
    const a = agg.get(k) || { name: v.name, phone: v.phone, amount: 0, items: 0, due: null };
    a.amount += v.bal; a.items += 1;
    if (v.due && v.due.length === 8 && (!a.due || v.due < a.due)) a.due = v.due;
    agg.set(k, a);
  }
  const list = [...agg.values()];
  const total = list.reduce((s, a) => s + a.amount, 0);
  console.log(`집계: 학생 ${list.length}명 · 미납 총액 ${Math.round(total).toLocaleString()}원 · 항목 ${seen.size}건`);

  const c = new Client({ host: process.env.PGHOST, port: +(process.env.PGPORT||5432), user: process.env.PGUSER,
    password: process.env.PGPASSWORD, database: 'postgres', ssl: { rejectUnauthorized: false } });
  await c.connect();
  await c.query('delete from branch_unpaid where branch_id=$1', [branchId]);
  const names = list.map(a => a.name), phones = list.map(a => a.phone),
        amounts = list.map(a => Math.round(a.amount)), items = list.map(a => a.items),
        dues = list.map(a => a.due ? `${a.due.slice(0,4)}-${a.due.slice(4,6)}-${a.due.slice(6,8)}` : null);
  await c.query(`insert into branch_unpaid (branch_id,student_name,phone,amount,items,earliest_due)
    select $1, * from unnest($2::text[],$3::text[],$4::bigint[],$5::int[],$6::date[])`,
    [branchId, names, phones, amounts, items, dues]);
  await c.query(`update metrics_snapshot set unpaid_total=$2, unpaid_count=$3, updated_at=now() where branch_id=$1`,
    [branchId, Math.round(total), list.length]);
  const v = await c.query('select count(*) n, sum(amount) s from branch_unpaid where branch_id=$1', [branchId]);
  console.log('적재 검증:', v.rows[0]);
  await c.end();
  console.log('🎉 완료');
})().catch(e => { console.error('❌', e.message); process.exit(1); });
