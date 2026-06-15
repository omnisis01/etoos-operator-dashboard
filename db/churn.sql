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
