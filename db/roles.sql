-- 계정 층위(4단계) 구조 정의 — (1)대표·임원 = (2)본사 담당직원 > (3)가맹지점 원장 > (4)지점 직원
-- 실행: schema.sql 이후 Supabase SQL Editor에서 RUN. 기존 exec/director 데이터와 하위호환.
--
-- 층위 원칙
--   · 데이터 범위:  exec·hq_staff = 전사(모든 지점) / director·staff = 자기 지점만
--   · 매출·미수금:  staff(지점 직원)는 차단 — 원장 이상만 (설문: 직원 노출 시 급여 불만 등 리스크)
--   · 관리 권한:    exec만 (계정 발급·전사 설정). '대표·임원 = 본사 담당'은 조회 범위가 동급이라는 뜻이며
--                   관리 권한은 exec가 상위.

-- 1) user_role enum 확장 (기존: 'exec','director')
alter type user_role add value if not exists 'hq_staff';   -- 본사 담당직원
alter type user_role add value if not exists 'staff';      -- 지점 직원

-- 2) 현재 사용자 role 조회
create or replace function my_role() returns user_role language sql stable as $$
  select role from profiles where id = auth.uid();
$$;

-- 3) 위계 서열 — 숫자가 클수록 상위 (exec=4 > hq_staff=3 > director=2 > staff=1)
create or replace function role_rank(r user_role) returns int language sql immutable as $$
  select case r when 'exec' then 4 when 'hq_staff' then 3 when 'director' then 2 else 1 end;
$$;

-- 4) 전사 데이터 접근층(본사층) 여부 — exec와 hq_staff 동급
--    기존 정책들이 is_exec()를 쓰므로, is_exec()를 '본사층' 의미로 재정의해 정책 재작성 없이 확장.
create or replace function is_exec() returns boolean language sql stable as $$
  select my_role() in ('exec','hq_staff');
$$;
create or replace function is_hq() returns boolean language sql stable as $$
  select is_exec();     -- 의미가 명확한 별칭 (신규 정책은 is_hq() 사용 권장)
$$;

-- 5) 매출·미수금 열람 가능 여부 — staff 차단
create or replace function can_view_sales() returns boolean language sql stable as $$
  select my_role() in ('exec','hq_staff','director');
$$;

-- 6) 매출성 테이블 RLS 적용 예 (실제 적용 시 테이블별로 기존 *_read 정책을 대체)
--    create policy payments_read on payments for select
--      using ( can_view_sales() and (is_hq() or branch_id = my_branch()) );
