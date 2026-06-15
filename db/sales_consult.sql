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
