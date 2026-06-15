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
