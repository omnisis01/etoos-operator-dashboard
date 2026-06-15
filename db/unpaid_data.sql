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
