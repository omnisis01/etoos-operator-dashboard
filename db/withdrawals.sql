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
