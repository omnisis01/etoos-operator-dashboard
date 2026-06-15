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
      { name:"김○○", amount:980000, items:2, due:"2026-06-30" },
      { name:"정○○", amount:850000, items:3, due:"2026-06-30" },
      { name:"윤○○", amount:760000, items:1, due:"2026-07-20" },
      { name:"송○○", amount:620000, items:2, due:"2026-07-20" },
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
    snap: { students:9840, occupancy:79, revenueEok:31.2, churnRate:4.1, unpaidEok:2.4, withdrawMonth:438, withdrawYtd:3394 },
    daily: { months:MONTHS, revenue:[26,27,29,28,30,31.2], students:[9200,9350,9500,9620,9720,9840] },
    barWithdraw: { labels:["이천기숙","독학기숙","대치","분당정자"], values:[437,372,191,122] },
    region: [ {label:"경기/인천",value:1100,pct:42},{label:"서울",value:760,pct:29},{label:"영남",value:430,pct:16},{label:"기타",value:340,pct:13} ],
    reasonsAll: [ {label:"성적 부진",pct:39},{label:"타 학원",pct:33},{label:"번아웃",pct:17},{label:"비용",pct:11} ],
    compare: { branches: [
      { name:"대치", ytd:191, month:32, cur:0, rep:32 },
      { name:"분당정자", ytd:122, month:16, cur:0, rep:16 },
      { name:"독학기숙학원", ytd:372, month:51, cur:0, rep:51 },
      { name:"이천기숙학원", ytd:437, month:54, cur:140, rep:297 },
    ]},
    directTable: [
      { name:"이천기숙학원", region:"경기/인천", type:"직영기숙", ytd:437, cur:140, rep:297, prev:665, month:54, today:0 },
      { name:"독학기숙학원", region:"경기/인천", type:"직영기숙", ytd:372, cur:43, rep:329, prev:653, month:51, today:7 },
      { name:"대치", region:"서울", type:"직영", ytd:191, cur:12, rep:179, prev:182, month:32, today:3 },
      { name:"분당정자", region:"경기/인천", type:"직영", ytd:122, cur:17, rep:105, prev:186, month:16, today:0 },
    ],
  },
};

// ── DB 조회 (Supabase) ────────────────────────────────────
async function dbBranch(branchId) {
  const [snapR, dailyR, riskR, payR, reasonR, actR] = await Promise.all([
    sb.from("metrics_snapshot").select("*").eq("branch_id", branchId).single(),
    sb.from("daily_metrics").select("*").eq("branch_id", branchId).order("date"),
    sb.from("churn_risks").select("score,level,signals,students(name)").eq("branch_id", branchId).order("score",{ascending:false}),
    sb.from("branch_unpaid").select("student_name,amount,items,earliest_due").eq("branch_id", branchId).order("amount",{ascending:false}).limit(8),
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
    payments: (payR.data||[]).map(r=>({ name:r.student_name, amount:r.amount, items:r.items, due:r.earliest_due })),
    reasons: (reasonR.data||[]).map(r=>({ label:r.reason, pct:Number(r.pct) })),
    newReturned: MOCK.branch.newReturned,   // (집계 뷰 추가 전까지 보조값)
    weekdayConsult: MOCK.branch.weekdayConsult,
    actions: (actR.data||[]).map(r=>({ priority:r.priority, title:r.title, time:(r.due_time||"").slice(0,5) })),
  };
}

async function dbHq() {
  const [sumR, monR, reaR, wdR] = await Promise.all([
    sb.from("hq_summary").select("*").eq("id", 1).single(),
    sb.from("hq_monthly").select("*").order("month"),
    sb.from("churn_reasons").select("reason,pct,rank").eq("scope", "all").order("rank"),
    sb.from("branch_withdrawals").select("ytd_total,month_total,today_total,ytd_current,ytd_repeat,prev_year,branches(name,region,type)"),
  ]);
  const s = sumR.data || {};
  const mon = monR.data || [];
  const wd = (wdR.data || []).filter(w => w.branches);
  // 권역별 금년 퇴원 집계
  const byReg = {};
  wd.forEach(w => { const r = w.branches.region || "기타"; byReg[r] = (byReg[r]||0) + (w.ytd_total||0); });
  const regArr = Object.entries(byReg).sort((a,b)=>b[1]-a[1]);
  const regTotal = regArr.reduce((a,x)=>a+x[1],0) || 1;
  const top = regArr.slice(0,3); const etc = regArr.slice(3).reduce((a,x)=>a+x[1],0);
  const region = top.map(([label,v])=>({label,value:v,pct:Math.round(v/regTotal*100)}));
  if (etc>0) region.push({label:"기타",value:etc,pct:Math.round(etc/regTotal*100)});
  // 직영점 (퇴원 바차트 + 테이블)
  const direct = wd.filter(w => (w.branches.type||"").includes("direct")).sort((a,b)=>b.ytd_total-a.ytd_total);
  return {
    snap: { students:s.total_students, occupancy:Number(s.occupancy), revenueEok:Number(s.mtd_revenue_eok),
      churnRate:Number(s.churn_rate), unpaidEok:Number(s.unpaid_eok),
      withdrawMonth:s.month_withdraw, withdrawYtd:s.ytd_withdraw },
    daily: { months:mon.map(r=>new Date(r.month).getMonth()+1+"월"),
      revenue:mon.map(r=>Number(r.revenue_eok)), students:mon.map(r=>r.students) },
    region,
    reasonsAll: (reaR.data||[]).map(r=>({ label:r.reason, pct:Number(r.pct) })),
    barWithdraw: { labels:direct.map(w=>w.branches.name), values:direct.map(w=>w.ytd_total) },
    compare: { branches: wd.map(w=>({ name:w.branches.name, ytd:w.ytd_total, month:w.month_total,
      cur:w.ytd_current, rep:w.ytd_repeat })).sort((a,b)=>b.ytd-a.ytd) },
    directTable: direct.map(w=>({ name:w.branches.name, region:w.branches.region,
      type:(w.branches.type||"").includes("boarding")?"직영기숙":"직영",
      ytd:w.ytd_total, cur:w.ytd_current, rep:w.ytd_repeat, prev:w.prev_year, month:w.month_total, today:w.today_total })),
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
