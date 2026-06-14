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
