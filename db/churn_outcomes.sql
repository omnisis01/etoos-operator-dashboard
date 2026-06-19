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
