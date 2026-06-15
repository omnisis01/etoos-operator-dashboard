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
