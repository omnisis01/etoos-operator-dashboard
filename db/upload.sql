-- ============================================================
--  업로드 기능용 쓰기 권한 (RLS) — 운영자가 자기 지점 지표를 upsert
-- ============================================================
-- 로그인 사용자: 임원은 전 지점, 원장은 자기 지점만 쓰기 가능
do $$ begin
  create policy snap_write on metrics_snapshot for all to authenticated
    using (is_exec() or branch_id = my_branch())
    with check (is_exec() or branch_id = my_branch());
exception when duplicate_object then null; end $$;
