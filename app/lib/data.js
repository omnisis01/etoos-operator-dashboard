// ──────────────────────────────────────────────────────────
//  데이터 레이어 — 대시보드가 호출하는 단일 출처
//  USE_MOCK 이면 샘플 데이터, 아니면 Supabase 조회.
//  반환 형태는 양쪽이 동일 → 화면 코드는 출처를 몰라도 됨.
// ──────────────────────────────────────────────────────────
const MONTHS = ["1월","2월","3월","4월","5월","6월"];
const COLORS = ["#A66BFF","#EC4899","#22D3EE","#4F7CFF"];

// ── MOCK (현재 대시보드 수치와 동일) ──────────────────────
const MOCK = {
  branch: {
    snap: { total_students:187, n_repeat:94, n_current:93, occupancy:82,
      mtd_revenue:18400000, unpaid_total:4120000, unpaid_count:7,
      attend:{present:154,late:3,absent:2,long:5,onleave:7},
      week_enroll:4, week_withdraw:1, month_enroll:13, month_withdraw:4,
      percentile_rank:18 },
    daily: { months:MONTHS, newEnroll:[13,15,12,14,16,20], withdraw:[4,3,5,4,6,5],
      revenue:[1450,1520,1380,1610,1720,1840] },
    risks: [
      { name:"홍○○", level:"urgent", score:94, signals:["순공 −45%","상담기피 12일","'힘들다' 감지","앱 미접속 5일"] },
      { name:"김○○", level:"urgent", score:88, signals:["모의고사 2회↓","질문예약 0건","결석 3회","학부모 문의↑"] },
      { name:"박○○", level:"urgent", score:81, signals:["부정 게시글","'다른 곳' 감지","순공 −32%"] },
      { name:"이○○", level:"watch",  score:62, signals:["집중도 3주 하락","상담 간격 증가","목표 격차 확대"] },
      { name:"최○○", level:"watch",  score:57, signals:["피로 누적","루틴 붕괴 조짐","팔로업 필요"] },
    ],
    payments: [
      { name:"김○○", days:31, amount:980000, note:"N수 · 2회 발송 · 회수 지연 위험" },
      { name:"정○○", days:18, amount:850000, note:"재학 · 1회 발송" },
      { name:"윤○○", days:15, amount:760000, note:"N수 · 1회 발송" },
      { name:"송○○", days:9,  amount:620000, note:"재학 · 미발송" },
    ],
    reasons: [ {label:"성적 부진",pct:42},{label:"타 학원",pct:31},{label:"번아웃",pct:18},{label:"비용",pct:9} ],
    newReturned: { new:37.2, returned:62.8 },
    weekdayConsult: [12,5,18,9,22,14],
    actions: [
      { priority:"urgent", title:"홍○○ 즉시 상담", time:"09:30" },
      { priority:"urgent", title:"오르비 게시글 대응", time:"10:00" },
      { priority:"high",   title:"미납 7명 발송", time:"11:00" },
      { priority:"high",   title:"특생 12명 연락", time:"13:00" },
      { priority:"followup", title:"최○○ 상담", time:"15:00" },
      { priority:"followup", title:"주간 보고서 제출", time:"17:00" },
    ],
  },
  hq: {
    snap: { students:9840, occupancy:79, revenueEok:31.2, churnRate:4.1, unpaidEok:2.4 },
    daily: { months:MONTHS, revenue:[26,27,29,28,30,31.2], students:[9200,9350,9500,9620,9720,9840] },
    barBranch: { labels:["강남","수원","강남구","부산","인천","대구"], values:[2.41,1.92,1.84,1.52,1.38,1.21] },
    region: [ {label:"수도권",pct:45,amt:14.2},{label:"영남",pct:26,amt:8.1},{label:"충청",pct:16,amt:4.9},{label:"호남·기타",pct:13,amt:4.0} ],
    reasonsAll: [ {label:"성적 부진",pct:39},{label:"타 학원",pct:33},{label:"번아웃",pct:17},{label:"비용",pct:11} ],
  },
};

// ── DB 조회 (Supabase) ────────────────────────────────────
async function dbBranch(branchId) {
  const [snapR, dailyR, riskR, payR, reasonR, actR] = await Promise.all([
    sb.from("metrics_snapshot").select("*").eq("branch_id", branchId).single(),
    sb.from("daily_metrics").select("*").eq("branch_id", branchId).order("date"),
    sb.from("churn_risks").select("score,level,signals,students(name)").eq("branch_id", branchId).order("score",{ascending:false}),
    sb.from("payments").select("amount,due_date,reminders_sent,students(name,type)").eq("branch_id", branchId).eq("status","unpaid").order("due_date"),
    sb.from("churn_reasons").select("*").eq("scope","branch").eq("branch_id", branchId).order("rank"),
    sb.from("action_items").select("*").eq("branch_id", branchId).order("due_time"),
  ]);
  const s = snapR.data || {};
  const d = dailyR.data || [];
  const today = new Date();
  const daysAgo = (iso) => Math.round((today - new Date(iso)) / 86400000);
  return {
    snap: { total_students:s.total_students, n_repeat:s.n_repeat, n_current:s.n_current,
      occupancy:s.occupancy, mtd_revenue:s.mtd_revenue, unpaid_total:s.unpaid_total, unpaid_count:s.unpaid_count,
      attend:{present:s.attend_present,late:s.attend_late,absent:s.attend_absent,long:s.attend_long,onleave:s.attend_onleave},
      week_enroll:s.week_enroll, week_withdraw:s.week_withdraw, month_enroll:s.month_enroll, month_withdraw:s.month_withdraw,
      percentile_rank:s.percentile_rank },
    daily: { months:d.map(r=>new Date(r.date).getMonth()+1+"월"),
      newEnroll:d.map(r=>r.new_enrollments), withdraw:d.map(r=>r.withdrawals),
      revenue:d.map(r=>Math.round(r.revenue/10000)) },
    risks: (riskR.data||[]).map(r=>({ name:r.students?.name, level:r.level, score:r.score, signals:r.signals||[] })),
    payments: (payR.data||[]).map(r=>({ name:r.students?.name, days:daysAgo(r.due_date), amount:r.amount, note:`${r.students?.type==="repeat"?"N수":"재학"} · ${r.reminders_sent?r.reminders_sent+"회 발송":"미발송"}` })),
    reasons: (reasonR.data||[]).map(r=>({ label:r.reason, pct:Number(r.pct) })),
    newReturned: MOCK.branch.newReturned,   // (집계 뷰 추가 전까지 보조값)
    weekdayConsult: MOCK.branch.weekdayConsult,
    actions: (actR.data||[]).map(r=>({ priority:r.priority, title:r.title, time:(r.due_time||"").slice(0,5) })),
  };
}

async function dbHq() {
  const [sumR, monR, regR, reaR, brR] = await Promise.all([
    sb.from("hq_summary").select("*").eq("id", 1).single(),
    sb.from("hq_monthly").select("*").order("month"),
    sb.from("hq_region").select("*").order("revenue_eok", { ascending: false }),
    sb.from("churn_reasons").select("reason,pct,rank").eq("scope", "all").order("rank"),
    sb.from("metrics_snapshot").select("mtd_revenue,branches(name)").order("mtd_revenue", { ascending: false }),
  ]);
  const s = sumR.data || {};
  const mon = monR.data || [];
  const reg = regR.data || [];
  const total = reg.reduce((a, r) => a + Number(r.revenue_eok), 0) || 1;
  const br = brR.data || [];
  const shortName = (n) => (n || "").split(" ")[0];
  return {
    snap: { students:s.total_students, occupancy:Number(s.occupancy), revenueEok:Number(s.mtd_revenue_eok),
      churnRate:Number(s.churn_rate), unpaidEok:Number(s.unpaid_eok) },
    daily: { months:mon.map(r=>new Date(r.month).getMonth()+1+"월"),
      revenue:mon.map(r=>Number(r.revenue_eok)), students:mon.map(r=>r.students) },
    region: reg.map(r=>({ label:r.region, amt:Number(r.revenue_eok), pct:Math.round(Number(r.revenue_eok)/total*100) })),
    reasonsAll: (reaR.data||[]).map(r=>({ label:r.reason, pct:Number(r.pct) })),
    barBranch: { labels:br.map(b=>shortName(b.branches?.name)), values:br.map(b=>+(b.mtd_revenue/1e8).toFixed(2)) },
  };
}

// ── 공개 API ──────────────────────────────────────────────
const DATA = {
  async branch(branchId) {
    if (window.USE_MOCK || !branchId) return MOCK.branch;   // 임원(지점 미지정)은 샘플
    try { return await dbBranch(branchId); }
    catch (e) { console.warn("지점 DB 조회 실패 → MOCK 사용", e); return MOCK.branch; }
  },
  async hq() {
    if (window.USE_MOCK) return MOCK.hq;
    try { return await dbHq(); }
    catch (e) { console.warn("전사 DB 조회 실패 → MOCK 사용", e); return MOCK.hq; }
  },
};
