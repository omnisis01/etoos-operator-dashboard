-- 복구 1/2 — 테이블·기본데이터·권한 enum (자동 생성: scripts/build-restore.sh, 직접 수정 금지)

-- ================= db/schema.sql =================
-- ============================================================
--  이투스ECI 운영자 대시보드 — DB 스키마 (PostgreSQL / Supabase)
--  실행: Supabase 프로젝트 > SQL Editor 에 붙여넣고 RUN
--  순서: 1) schema.sql  2) seed.sql
-- ============================================================

-- Supabase 기본 확장 (UUID 생성)
create extension if not exists pgcrypto;

-- ── ENUM 타입 ────────────────────────────────────────────────
do $$ begin
  create type user_role        as enum ('exec','director');                 -- 임원 / 원장
  create type branch_type      as enum ('direct','franchise');              -- 직영 / 가맹
  create type student_type     as enum ('repeat','current');                -- N수 / 재학
  create type student_status   as enum ('active','onleave','withdrawn');    -- 재원 / 휴원 / 퇴원
  create type attend_status    as enum ('present','late','absent','long_absent','onleave');
  create type payment_status   as enum ('paid','unpaid','partial');
  create type risk_level       as enum ('urgent','watch');                  -- 긴급 / 주의
  create type sentiment        as enum ('positive','neutral','negative');
  create type action_priority  as enum ('urgent','high','followup');
exception when duplicate_object then null; end $$;

-- ── 지점 ─────────────────────────────────────────────────────
create table if not exists branches (
  id           uuid primary key default gen_random_uuid(),
  name         text not null,
  region       text not null,                 -- 수도권/영남/충청/호남/강원·제주
  type         branch_type not null default 'franchise',
  seats        int  not null default 0,
  created_at   timestamptz not null default now()
);

-- ── 운영자 프로필 (auth.users 1:1) ───────────────────────────
create table if not exists profiles (
  id           uuid primary key references auth.users(id) on delete cascade,
  name         text not null,
  role         user_role not null default 'director',
  branch_id    uuid references branches(id),  -- 임원은 null(전사)
  created_at   timestamptz not null default now()
);

-- ── 재원생 ───────────────────────────────────────────────────
create table if not exists students (
  id           uuid primary key default gen_random_uuid(),
  branch_id    uuid not null references branches(id) on delete cascade,
  name         text not null,
  type         student_type not null default 'current',
  status       student_status not null default 'active',
  enrolled_at  date,
  withdrawn_at date,
  created_at   timestamptz not null default now()
);
create index if not exists idx_students_branch on students(branch_id);

-- ── 출결 ─────────────────────────────────────────────────────
create table if not exists attendance (
  id           uuid primary key default gen_random_uuid(),
  student_id   uuid not null references students(id) on delete cascade,
  branch_id    uuid not null references branches(id) on delete cascade,
  date         date not null,
  status       attend_status not null,
  unique (student_id, date)
);
create index if not exists idx_attend_branch_date on attendance(branch_id, date);

-- ── 수납 / 미납 ──────────────────────────────────────────────
create table if not exists payments (
  id             uuid primary key default gen_random_uuid(),
  student_id     uuid not null references students(id) on delete cascade,
  branch_id      uuid not null references branches(id) on delete cascade,
  amount         int  not null,                 -- 원
  due_date       date not null,
  paid_at        date,
  status         payment_status not null default 'unpaid',
  reminders_sent int not null default 0,
  created_at     timestamptz not null default now()
);
create index if not exists idx_pay_branch_status on payments(branch_id, status);

-- ── 상담 ─────────────────────────────────────────────────────
create table if not exists consultations (
  id           uuid primary key default gen_random_uuid(),
  student_id   uuid not null references students(id) on delete cascade,
  branch_id    uuid not null references branches(id) on delete cascade,
  date         date not null,
  counselor    text,
  summary      text,
  sentiment    sentiment,
  keywords     text[] default '{}',
  created_at   timestamptz not null default now()
);

-- ── 퇴원 위험 (AI 산출) ──────────────────────────────────────
create table if not exists churn_risks (
  id           uuid primary key default gen_random_uuid(),
  student_id   uuid not null references students(id) on delete cascade,
  branch_id    uuid not null references branches(id) on delete cascade,
  score        int  not null check (score between 0 and 100),
  level        risk_level not null,
  signals      text[] default '{}',
  computed_at  timestamptz not null default now()
);
create index if not exists idx_risk_branch on churn_risks(branch_id);

-- ── 일별 지표 (차트 백업용 집계 캐시) ───────────────────────
create table if not exists daily_metrics (
  branch_id        uuid not null references branches(id) on delete cascade,
  date             date not null,
  revenue          bigint default 0,           -- 원
  new_enrollments  int default 0,
  withdrawals      int default 0,
  attendance_rate  numeric(5,2) default 0,     -- %
  occupancy        numeric(5,2) default 0,     -- %
  primary key (branch_id, date)
);

-- ── 이탈 사유 집계 ───────────────────────────────────────────
create table if not exists churn_reasons (
  id           uuid primary key default gen_random_uuid(),
  scope        text not null,                  -- 'branch' | 'region' | 'all'
  branch_id    uuid references branches(id),
  reason       text not null,
  pct          numeric(5,2) not null,
  period_start date,
  rank         int
);

-- ── 지점 헤드라인 스냅샷 (상단 카드 한 줄 조회용) ───────────
create table if not exists metrics_snapshot (
  branch_id        uuid primary key references branches(id) on delete cascade,
  total_students   int default 0,
  n_repeat         int default 0,   -- N수
  n_current        int default 0,   -- 재학
  occupancy        numeric(5,2) default 0,
  mtd_revenue      bigint default 0,  -- 당월 누적 매출(원)
  yesterday_revenue bigint default 0,
  unpaid_total     bigint default 0,
  unpaid_count     int default 0,
  attend_present   int default 0,
  attend_late      int default 0,
  attend_absent    int default 0,
  attend_long      int default 0,
  attend_onleave   int default 0,
  week_enroll      int default 0,
  week_withdraw    int default 0,
  month_enroll     int default 0,
  month_withdraw   int default 0,
  percentile_rank  numeric(5,2),     -- 전 가맹점 대비 상위 %
  updated_at       timestamptz default now()
);

-- ── 액션 아이템 (오늘 할 일 / 액션 플랜) ────────────────────
create table if not exists action_items (
  id           uuid primary key default gen_random_uuid(),
  branch_id    uuid references branches(id) on delete cascade,
  priority     action_priority not null,
  title        text not null,
  due_time     time,
  done         boolean not null default false,
  created_at   timestamptz not null default now()
);

-- ============================================================
--  RLS (행 수준 보안) — 임원=전사, 원장=자기 지점
-- ============================================================
alter table branches      enable row level security;
alter table students      enable row level security;
alter table attendance    enable row level security;
alter table payments      enable row level security;
alter table consultations enable row level security;
alter table churn_risks   enable row level security;
alter table daily_metrics enable row level security;
alter table churn_reasons enable row level security;
alter table action_items  enable row level security;
alter table metrics_snapshot enable row level security;
alter table profiles      enable row level security;

-- 현재 사용자가 임원인가?
create or replace function is_exec() returns boolean language sql stable as $$
  select exists (select 1 from profiles p where p.id = auth.uid() and p.role = 'exec');
$$;
-- 현재 사용자의 지점
create or replace function my_branch() returns uuid language sql stable as $$
  select branch_id from profiles where id = auth.uid();
$$;

-- 본인 프로필
create policy profiles_self on profiles for select using (id = auth.uid());

-- 신규 로그인 계정 → profiles 자동 생성 (기본 원장, 지점 미지정)
create or replace function handle_new_user() returns trigger
  language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, name, role)
  values (new.id, coalesce(new.raw_user_meta_data->>'name','운영자'), 'director')
  on conflict (id) do nothing;
  return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function handle_new_user();

-- 공통 정책: 임원은 전부, 원장은 자기 지점만 (branch_id 기준)
do $$
declare t text;
begin
  foreach t in array array['students','attendance','payments','consultations','churn_risks','daily_metrics','action_items','metrics_snapshot']
  loop
    execute format($f$
      create policy %1$s_read on %1$I for select
        using ( is_exec() or branch_id = my_branch() );
    $f$, t);
  end loop;
end $$;

-- 지점 목록: 임원 전체 / 원장 자기 지점
create policy branches_read on branches for select
  using ( is_exec() or id = my_branch() );

-- 이탈 사유: 전사/권역은 임원, 지점은 해당 원장도
create policy reasons_read on churn_reasons for select
  using ( is_exec() or (scope = 'branch' and branch_id = my_branch()) );

-- ================= db/seed.sql =================
-- ============================================================
--  샘플 데이터 — 대시보드 더미 수치와 동일하게 적재
--  실행: schema.sql 실행 후 SQL Editor 에서 RUN
-- ============================================================

-- ── 지점 (전사 모드 테이블과 동일) ──────────────────────────
insert into branches (id, name, region, type, seats) values
  ('11111111-0000-0000-0000-000000000001','강남 직영점','수도권','direct',250),
  ('11111111-0000-0000-0000-000000000002','수원 영통점','수도권','franchise',233),
  ('11111111-0000-0000-0000-000000000003','강남구 직영점','수도권','direct',228),  -- ★ 내 지점
  ('11111111-0000-0000-0000-000000000004','부산 서면점','영남','franchise',216),
  ('11111111-0000-0000-0000-000000000005','인천 송도점','수도권','franchise',205),
  ('11111111-0000-0000-0000-000000000006','대구 범어점','영남','franchise',207)
on conflict (id) do nothing;

-- ── 내 지점(강남구 직영점) 헤드라인 스냅샷 ──────────────────
insert into metrics_snapshot (branch_id,total_students,n_repeat,n_current,occupancy,
  mtd_revenue,yesterday_revenue,unpaid_total,unpaid_count,
  attend_present,attend_late,attend_absent,attend_long,attend_onleave,
  week_enroll,week_withdraw,month_enroll,month_withdraw,percentile_rank)
values ('11111111-0000-0000-0000-000000000003',187,94,93,82.0,
  18400000,1270000,4120000,7,
  154,3,2,5,7,
  4,1,13,4,18.0)
on conflict (branch_id) do update set updated_at = now();

-- 전사 지점별 당월 매출 / 등급용 스냅샷 (전사 테이블 차트)
insert into metrics_snapshot (branch_id,total_students,occupancy,mtd_revenue,percentile_rank) values
  ('11111111-0000-0000-0000-000000000001',228,91.0,241000000,8.0),
  ('11111111-0000-0000-0000-000000000002',196,84.0,192000000,12.0),
  ('11111111-0000-0000-0000-000000000004',164,76.0,152000000,24.0),
  ('11111111-0000-0000-0000-000000000005',152,74.0,138000000,31.0),
  ('11111111-0000-0000-0000-000000000006',141,68.0,121000000,42.0)
on conflict (branch_id) do nothing;

-- ── 재원생 (위험·미납 명단의 실제 학생) ─────────────────────
insert into students (id, branch_id, name, type, status, enrolled_at) values
  ('22222222-0000-0000-0000-000000000001','11111111-0000-0000-0000-000000000003','홍○○','repeat','active','2025-03-02'),
  ('22222222-0000-0000-0000-000000000002','11111111-0000-0000-0000-000000000003','김○○','repeat','active','2025-03-04'),
  ('22222222-0000-0000-0000-000000000003','11111111-0000-0000-0000-000000000003','박○○','current','active','2025-04-01'),
  ('22222222-0000-0000-0000-000000000004','11111111-0000-0000-0000-000000000003','이○○','current','active','2025-02-11'),
  ('22222222-0000-0000-0000-000000000005','11111111-0000-0000-0000-000000000003','최○○','repeat','active','2025-01-20'),
  ('22222222-0000-0000-0000-000000000006','11111111-0000-0000-0000-000000000003','정○○','current','active','2025-05-09'),
  ('22222222-0000-0000-0000-000000000007','11111111-0000-0000-0000-000000000003','윤○○','repeat','active','2025-04-15'),
  ('22222222-0000-0000-0000-000000000008','11111111-0000-0000-0000-000000000003','송○○','current','active','2025-05-20')
on conflict (id) do nothing;

-- ── 퇴원 위험 (홍94·김88·박81·이62·최57) ────────────────────
insert into churn_risks (student_id, branch_id, score, level, signals) values
  ('22222222-0000-0000-0000-000000000001','11111111-0000-0000-0000-000000000003',94,'urgent', array['순공 −45%','상담기피 12일','부정어 감지','앱 미접속 5일']),
  ('22222222-0000-0000-0000-000000000002','11111111-0000-0000-0000-000000000003',88,'urgent', array['모의고사 2회↓','질문예약 0건','결석 3회','학부모 문의↑']),
  ('22222222-0000-0000-0000-000000000003','11111111-0000-0000-0000-000000000003',81,'urgent', array['부정 게시글','다른 곳 감지','순공 −32%']),
  ('22222222-0000-0000-0000-000000000004','11111111-0000-0000-0000-000000000003',62,'watch',  array['집중도 3주 하락','상담 간격 증가','목표 격차 확대']),
  ('22222222-0000-0000-0000-000000000005','11111111-0000-0000-0000-000000000003',57,'watch',  array['피로 누적','루틴 붕괴 조짐','팔로업 필요']);

-- ── 미납 (김98·정85·윤76·송62) ───────────────────────────────
insert into payments (student_id, branch_id, amount, due_date, status, reminders_sent) values
  ('22222222-0000-0000-0000-000000000002','11111111-0000-0000-0000-000000000003', 980000, current_date - 31, 'unpaid', 2),
  ('22222222-0000-0000-0000-000000000006','11111111-0000-0000-0000-000000000003', 850000, current_date - 18, 'unpaid', 1),
  ('22222222-0000-0000-0000-000000000007','11111111-0000-0000-0000-000000000003', 760000, current_date - 15, 'unpaid', 1),
  ('22222222-0000-0000-0000-000000000008','11111111-0000-0000-0000-000000000003', 620000, current_date - 9,  'unpaid', 0);

-- ── 상담 (홍·박) ─────────────────────────────────────────────
insert into consultations (student_id, branch_id, date, counselor, summary, sentiment, keywords) values
  ('22222222-0000-0000-0000-000000000001','11111111-0000-0000-0000-000000000003', current_date - 3, '담임','목표 대학 자신감 저하 반복. ''열심히 해도 안 될 것 같다'' 2회.', 'negative', array['자신감 저하','포기 신호','목표 재설정']),
  ('22222222-0000-0000-0000-000000000003','11111111-0000-0000-0000-000000000003', current_date - 4, '담임','타 학원 비교 발언, 커리큘럼 불만족. 학부모 전화 문의.', 'negative', array['타원 비교','불만족','학부모 연계']);

-- ── 일별 지표 (라인/영역 차트: 1~6월) ───────────────────────
insert into daily_metrics (branch_id, date, revenue, new_enrollments, withdrawals, attendance_rate, occupancy) values
  ('11111111-0000-0000-0000-000000000003','2026-01-01',14500000,13,4,79,78),
  ('11111111-0000-0000-0000-000000000003','2026-02-01',15200000,15,3,80,79),
  ('11111111-0000-0000-0000-000000000003','2026-03-01',13800000,12,5,78,79),
  ('11111111-0000-0000-0000-000000000003','2026-04-01',16100000,14,4,81,80),
  ('11111111-0000-0000-0000-000000000003','2026-05-01',17200000,16,6,82,81),
  ('11111111-0000-0000-0000-000000000003','2026-06-01',18400000,20,5,82,82)
on conflict (branch_id, date) do nothing;

-- ── 이탈 사유 (지점 / 전사) ──────────────────────────────────
insert into churn_reasons (scope, branch_id, reason, pct, rank) values
  ('branch','11111111-0000-0000-0000-000000000003','성적 부진',42,1),
  ('branch','11111111-0000-0000-0000-000000000003','타 학원',31,2),
  ('branch','11111111-0000-0000-0000-000000000003','번아웃',18,3),
  ('branch','11111111-0000-0000-0000-000000000003','비용',9,4),
  ('all', null,'성적 부진',39,1),
  ('all', null,'타 학원',33,2),
  ('all', null,'번아웃',17,3),
  ('all', null,'비용',11,4);

-- ── 액션 아이템 ──────────────────────────────────────────────
insert into action_items (branch_id, priority, title, due_time) values
  ('11111111-0000-0000-0000-000000000003','urgent','홍○○ 즉시 상담', '09:30'),
  ('11111111-0000-0000-0000-000000000003','urgent','오르비 게시글 대응','10:00'),
  ('11111111-0000-0000-0000-000000000003','high','미납 7명 발송','11:00'),
  ('11111111-0000-0000-0000-000000000003','high','특생 12명 연락','13:00'),
  ('11111111-0000-0000-0000-000000000003','followup','최○○ 상담','15:00'),
  ('11111111-0000-0000-0000-000000000003','followup','주간 보고서 제출','17:00');

-- ================= db/hq.sql =================
-- ============================================================
--  전사(임원) 집계 데이터 — schema.sql/seed.sql 이후 실행 (멱등)
-- ============================================================

-- 지점 스냅샷에 전사 테이블용 컬럼 추가
alter table metrics_snapshot add column if not exists grade text;
alter table metrics_snapshot add column if not exists mom_pct numeric;     -- 전월비 %
alter table metrics_snapshot add column if not exists churn_rate numeric;   -- 퇴원율 %
alter table metrics_snapshot add column if not exists unpaid_rate numeric;  -- 미납률 %

-- 지점별 등급·전월비·퇴원율·미납률 (+ 강남구 매출 단위 일관화: 1.84억)
update metrics_snapshot set grade='A', mom_pct=14, churn_rate=2.1, unpaid_rate=2.8 where branch_id='11111111-0000-0000-0000-000000000001';
update metrics_snapshot set grade='A', mom_pct=11, churn_rate=2.6, unpaid_rate=3.1 where branch_id='11111111-0000-0000-0000-000000000002';
update metrics_snapshot set grade='A', mom_pct=12, churn_rate=3.3, unpaid_rate=4.0, mtd_revenue=184000000 where branch_id='11111111-0000-0000-0000-000000000003';
update metrics_snapshot set grade='B', mom_pct=4,  churn_rate=4.4, unpaid_rate=5.2 where branch_id='11111111-0000-0000-0000-000000000004';
update metrics_snapshot set grade='B', mom_pct=-2, churn_rate=4.8, unpaid_rate=5.8 where branch_id='11111111-0000-0000-0000-000000000005';
update metrics_snapshot set grade='C', mom_pct=-7, churn_rate=6.2, unpaid_rate=7.4 where branch_id='11111111-0000-0000-0000-000000000006';

-- 강남구 월별 매출도 억 단위로 일관화 (×10)
update daily_metrics set revenue = revenue * 10
  where branch_id='11111111-0000-0000-0000-000000000003' and revenue < 100000000;

-- 전사 헤드라인 (단일 행)
create table if not exists hq_summary (
  id int primary key default 1,
  total_students int, occupancy numeric, mtd_revenue_eok numeric,
  churn_rate numeric, unpaid_eok numeric,
  constraint hq_summary_singleton check (id = 1)
);
insert into hq_summary (id,total_students,occupancy,mtd_revenue_eok,churn_rate,unpaid_eok)
values (1, 9840, 79, 31.2, 4.1, 2.4)
on conflict (id) do update set total_students=excluded.total_students,
  occupancy=excluded.occupancy, mtd_revenue_eok=excluded.mtd_revenue_eok,
  churn_rate=excluded.churn_rate, unpaid_eok=excluded.unpaid_eok;

-- 전사 월별 추이
create table if not exists hq_monthly (
  month date primary key, revenue_eok numeric, students int
);
insert into hq_monthly (month,revenue_eok,students) values
  ('2026-01-01',26,9200),('2026-02-01',27,9350),('2026-03-01',29,9500),
  ('2026-04-01',28,9620),('2026-05-01',30,9720),('2026-06-01',31.2,9840)
on conflict (month) do nothing;

-- 전사 권역별 매출 비중
create table if not exists hq_region (
  region text primary key, revenue_eok numeric
);
insert into hq_region (region,revenue_eok) values
  ('수도권',14.2),('영남',8.1),('충청',4.9),('호남·기타',4.0)
on conflict (region) do nothing;

-- RLS: 전사 집계는 임원만
alter table hq_summary enable row level security;
alter table hq_monthly enable row level security;
alter table hq_region  enable row level security;
do $$ begin
  create policy hq_summary_read on hq_summary for select using (is_exec());
  create policy hq_monthly_read on hq_monthly for select using (is_exec());
  create policy hq_region_read  on hq_region  for select using (is_exec());
exception when duplicate_object then null; end $$;

-- ================= db/upload.sql =================
-- ============================================================
--  업로드 기능용 쓰기 권한 (RLS) — 운영자가 자기 지점 지표를 upsert
-- ============================================================
-- 로그인 사용자: 임원은 전 지점, 원장은 자기 지점만 쓰기 가능
do $$ begin
  create policy snap_write on metrics_snapshot for all to authenticated
    using (is_exec() or branch_id = my_branch())
    with check (is_exec() or branch_id = my_branch());
exception when duplicate_object then null; end $$;

-- ================= db/unpaid_data.sql =================
-- ============================================================
--  ERP 미납(미수금) 적재용 테이블 — 학생별 집계 (직영점)
-- ============================================================
create table if not exists branch_unpaid (
  id           uuid primary key default gen_random_uuid(),
  branch_id    uuid not null references branches(id) on delete cascade,
  student_name text not null,
  phone        text,
  amount       bigint not null default 0,   -- 미납(미수)액 합계, 원
  items        int not null default 0,       -- 청구 항목 수
  earliest_due date,                          -- 가장 이른 납부마감일
  updated_at   timestamptz not null default now()
);
create index if not exists idx_unpaid_branch on branch_unpaid(branch_id, amount desc);

alter table branch_unpaid enable row level security;
do $$ begin
  create policy unpaid_read on branch_unpaid for select using (is_exec() or branch_id = my_branch());
  create policy unpaid_write on branch_unpaid for all to authenticated
    using (is_exec() or branch_id = my_branch()) with check (is_exec() or branch_id = my_branch());
exception when duplicate_object then null; end $$;

-- ================= db/withdrawals.sql =================
-- ============================================================
--  지점별 퇴원 집계 (ERP 퇴원생 보고서) + 전사 퇴원 요약
-- ============================================================
create table if not exists branch_withdrawals (
  branch_id     uuid primary key references branches(id) on delete cascade,
  ytd_total     int default 0,  -- 금년 누적 계
  ytd_current   int default 0,  -- 금년 재학생
  ytd_repeat    int default 0,  -- 금년 N수생
  prev_year     int default 0,  -- 전년 누적
  month_total   int default 0,  -- 금월
  month_current int default 0,
  month_repeat  int default 0,
  today_total   int default 0,  -- 금일
  updated_at    timestamptz default now()
);
alter table branch_withdrawals enable row level security;
do $$ begin
  create policy wd_read on branch_withdrawals for select using (is_exec() or branch_id = my_branch());
exception when duplicate_object then null; end $$;

-- 전사 요약에 실제 퇴원 수 컬럼 추가
alter table hq_summary add column if not exists ytd_withdraw   int;
alter table hq_summary add column if not exists month_withdraw int;

-- ================= db/sales_consult.sql =================
-- ============================================================
--  직영점 월매출 + 지점별 상담(금일) 집계
-- ============================================================
create table if not exists branch_sales (
  branch_id   uuid not null references branches(id) on delete cascade,
  period      text not null,             -- 예: '2026-06'
  net_revenue bigint not null default 0, -- 순매출(등록-환불), 원
  updated_at  timestamptz default now(),
  primary key (branch_id, period)
);
alter table branch_sales enable row level security;

create table if not exists branch_consult (
  branch_id    uuid primary key references branches(id) on delete cascade,
  new_enroll   int default 0,  -- 금일 신규 등록(계)
  phone        int default 0,  -- 전화상담(계)
  visit        int default 0,  -- 방문상담(계)
  total        int default 0,  -- 총 상담건수(계)
  updated_at   timestamptz default now()
);
alter table branch_consult enable row level security;

do $$ begin
  create policy sales_read   on branch_sales   for select using (is_exec() or branch_id = my_branch());
  create policy consult_read on branch_consult for select using (is_exec() or branch_id = my_branch());
exception when duplicate_object then null; end $$;

-- ================= db/attendance.sql =================
-- ============================================================
--  지점별 금일 출결 집계 (ERP 출결관리 화면 기준)
-- ============================================================
create table if not exists branch_attendance (
  branch_id   uuid primary key references branches(id) on delete cascade,
  date        date,
  present     int default 0,  -- 등원
  late        int default 0,  -- 지각
  absent      int default 0,  -- 결석
  early_leave int default 0,  -- 조퇴
  out_cnt     int default 0,  -- 외출
  left_cnt    int default 0,  -- 하원
  total       int default 0,  -- 명부 합계
  updated_at  timestamptz default now()
);
alter table branch_attendance enable row level security;
do $$ begin
  create policy attend_read on branch_attendance for select using (is_exec() or branch_id = my_branch());
exception when duplicate_object then null; end $$;

-- ================= db/churn.sql =================
-- ============================================================
--  퇴원 위험 점수 — 학생별 위험 요인 (4종 + 미납)
--  ERP에서 출결이력·순공시간·벌점·성적 추출 후 적재
-- ============================================================
create table if not exists churn_factors (
  id           uuid primary key default gen_random_uuid(),
  branch_id    uuid not null references branches(id) on delete cascade,
  student_name text not null,
  absence_rate numeric default 0,    -- 최근 결석+지각 비율(%)
  study_pct    numeric,              -- 순공 달성률(%) — null=데이터없음
  grade_delta  numeric default 0,    -- 등급 하락폭(+ = 하락)
  demerit      int default 0,        -- 누적 벌점
  unpaid_days  int default 0,        -- 미납 경과일
  updated_at   timestamptz default now()
);
create index if not exists idx_churn_branch on churn_factors(branch_id);
alter table churn_factors enable row level security;
do $$ begin
  create policy churn_read on churn_factors for select using (is_exec() or branch_id = my_branch());
exception when duplicate_object then null; end $$;

-- ================= db/churn_outcomes.sql =================
-- ============================================================
--  퇴원 위험 — 6대 팩터 보강 + 퇴원 라벨 스냅샷(churn_outcomes)
--  실제 퇴원 시 '그 시점의 팩터값 + 위험점수'를 기록 → 미래 보정용 정답지
-- ============================================================

-- 1) churn_factors 에 NLP 팩터 컬럼 보강 (상담 부정어 · 커뮤니티 부정글)
alter table churn_factors add column if not exists neg_score    numeric default 0;  -- 상담 부정어 강도(NLP 0~100)
alter table churn_factors add column if not exists community_neg numeric default 0;  -- 커뮤니티 부정글 강도(NLP 0~100)

-- churn_factors 쓰기 정책(업로드 delete+insert) — 없으면 생성
do $$ begin create policy churn_write on churn_factors for insert with check (is_exec() or branch_id = my_branch()); exception when duplicate_object then null; end $$;
do $$ begin create policy churn_del   on churn_factors for delete using      (is_exec() or branch_id = my_branch()); exception when duplicate_object then null; end $$;

-- 2) 퇴원 라벨 스냅샷 테이블
create table if not exists churn_outcomes (
  id            uuid primary key default gen_random_uuid(),
  branch_id     uuid not null references branches(id) on delete cascade,
  student_name  text not null,
  -- 퇴원 시점 팩터 스냅샷
  absence_rate  numeric,
  study_pct     numeric,
  grade_delta   numeric,
  unpaid_days   int,
  neg_score     numeric,
  community_neg numeric,
  -- 엔진 계산값(당시)
  risk_score    int,
  risk_level    text,
  signals       jsonb,
  withdraw_date date default current_date,
  recorded_at   timestamptz default now()
);
create index if not exists idx_outcome_branch on churn_outcomes(branch_id);

alter table churn_outcomes enable row level security;
do $$ begin create policy outcome_read  on churn_outcomes for select using      (is_exec() or branch_id = my_branch()); exception when duplicate_object then null; end $$;
do $$ begin create policy outcome_write on churn_outcomes for insert with check (is_exec() or branch_id = my_branch()); exception when duplicate_object then null; end $$;

-- ================= db/withdrawal_reasons.sql =================
-- ============================================================
--  상담일지 퇴원 사유 → 대시보드 (정규화 사전 + churn_reasons 보강)
--  원천: 상담일지 .xlsb [퇴원_N수 · 퇴원_윈터]  (파서: DATA pipeline/parse_sangdam_withdrawals.py)
-- ============================================================

-- 1) 정규화 사전 — 엑셀 원문(소분류) → 표준 코드. 운영자가 신규 표기를 직접 추가.
create table if not exists reason_code_map (
  raw_text    text primary key,   -- 엑셀 원문(소분류 표기, 변형 포함)
  reason_code text not null,      -- 표준 소분류 코드
  major_code  text not null,      -- 표준 대분류 코드 (ENV/PERSONAL/ETC ...)
  label       text not null,      -- 화면 표시명
  updated_at  timestamptz default now()
);

insert into reason_code_map(raw_text, reason_code, major_code, label) values
 ('등원전환불','NO_SHOW_REFUND','ENV','등원 전 환불'),
 ('타학원이동','MOVE_OTHER_ACADEMY','ENV','타학원 이동'),
 ('타학원 이동','MOVE_OTHER_ACADEMY','ENV','타학원 이동'),   -- 공백 변형
 ('독학','SELF_STUDY','ENV','독학 전환'),
 ('독학(집)','SELF_STUDY','ENV','독학 전환'),
 ('독학(독서실)','SELF_STUDY','ENV','독학 전환'),
 ('독서실','SELF_STUDY','ENV','독학 전환'),
 ('통학거리','DISTANCE','ENV','통학거리'),
 ('통학거리(이사)','DISTANCE','ENV','통학거리'),
 ('이사','DISTANCE','ENV','통학거리'),
 ('건강악화','HEALTH','PERSONAL','건강 악화'),
 ('재수포기','QUIT_REEXAM','ENV','재수 포기'),
 ('학원부적응','MALADJUST','ENV','학원 부적응'),
 ('타247이동','MOVE_247','ENV','타 247 이동'),
 ('기숙학원이동','MOVE_BOARDING','ENV','기숙학원 이동'),
 ('추가합격','ADMIT','PERSONAL','합격·진학'),
 ('수시합격','ADMIT','PERSONAL','합격·진학'),
 ('대학교합격','ADMIT','PERSONAL','합격·진학'),
 ('대학복학','ADMIT','PERSONAL','합격·진학'),
 ('가정형편','PERSONAL_FIN','PERSONAL','가정형편'),
 ('부모님반대','PERSONAL_OPP','PERSONAL','보호자 반대'),
 ('유학','ABROAD','ETC','유학'),
 ('급식문제','FACILITY','FACILITY','시설/급식')
on conflict (raw_text) do nothing;
-- 미매칭 표기는 reason_code='UNMAPPED' 으로 적재하여 격리(자동 추측 금지) → 운영자가 본 표에 추가.

-- 2) churn_reasons 보강 — 표준 코드·대분류·건수·시즌·출처
alter table churn_reasons add column if not exists reason_code text;
alter table churn_reasons add column if not exists major_code  text;
alter table churn_reasons add column if not exists cnt         int;
alter table churn_reasons add column if not exists season      text;   -- 'N수'|'정규'|'윈터'|'조기선발'|null(전체)
alter table churn_reasons add column if not exists source      text default 'erp';  -- 'sangdam'|'erp'

-- 3) 적재 예시 — 대치점, 상담일지 누적 1,297건 (파서 산출, scope='branch')
--    실적재 시 delete(해당 branch+source+season) 후 insert (멱등)
-- delete from churn_reasons where scope='branch' and source='sangdam' and branch_id = '<대치 branch_id>';
-- insert into churn_reasons(scope,branch_id,reason,reason_code,major_code,pct,cnt,rank,source) values
--  ('branch','<대치>','등원 전 환불','NO_SHOW_REFUND','ENV',49.7,645,1,'sangdam'),
--  ('branch','<대치>','타학원 이동','MOVE_OTHER_ACADEMY','ENV',15.2,197,2,'sangdam'),
--  ('branch','<대치>','독학 전환','SELF_STUDY','ENV',11.0,143,3,'sangdam'),
--  ('branch','<대치>','통학거리','DISTANCE','ENV',5.7,74,4,'sangdam'),
--  ('branch','<대치>','건강 악화','HEALTH','PERSONAL',3.9,51,5,'sangdam'),
--  ('branch','<대치>','재수 포기','QUIT_REEXAM','ENV',1.8,23,6,'sangdam'),
--  ('branch','<대치>','학원 부적응','MALADJUST','ENV',1.3,17,7,'sangdam'),
--  ('branch','<대치>','타 247 이동','MOVE_247','ENV',1.1,14,8,'sangdam');

alter table reason_code_map enable row level security;
do $$ begin create policy rcm_read on reason_code_map for select using (true); exception when duplicate_object then null; end $$;

-- ================= db/roles.sql (enum 추가분) =================
alter type user_role add value if not exists 'hq_staff';   -- 본사 담당직원
alter type user_role add value if not exists 'staff';      -- 지점 직원
