-- ============================================================
--  상담일지 퇴원 사유 → 대시보드 (정규화 사전 + churn_reasons 보강)
--  원천: 상담일지 .xlsb [퇴원_N수 · 퇴원_윈터]  (파서: DATA pipeline/parse_sangdam_withdrawals.py)
-- ============================================================

-- 1) 정규화 사전 — 엑셀 원문(소분류) → 표준 코드. 운영자가 신규 표기를 직접 추가.
create table if not exists reason_code_map (
  raw_text    text primary key,   -- 엑셀 원문(소분류 표기, 변형 포함)
  reason_code text not null,      -- 표준 소분류 코드
  major_code  text not null,      -- 표준 대분류 코드 (ENV/PERSONAL/ETC ...)
  label       text not null,      -- 화면 표시명
  updated_at  timestamptz default now()
);

insert into reason_code_map(raw_text, reason_code, major_code, label) values
 ('등원전환불','NO_SHOW_REFUND','ENV','등원 전 환불'),
 ('타학원이동','MOVE_OTHER_ACADEMY','ENV','타학원 이동'),
 ('타학원 이동','MOVE_OTHER_ACADEMY','ENV','타학원 이동'),   -- 공백 변형
 ('독학','SELF_STUDY','ENV','독학 전환'),
 ('독학(집)','SELF_STUDY','ENV','독학 전환'),
 ('독학(독서실)','SELF_STUDY','ENV','독학 전환'),
 ('독서실','SELF_STUDY','ENV','독학 전환'),
 ('통학거리','DISTANCE','ENV','통학거리'),
 ('통학거리(이사)','DISTANCE','ENV','통학거리'),
 ('이사','DISTANCE','ENV','통학거리'),
 ('건강악화','HEALTH','PERSONAL','건강 악화'),
 ('재수포기','QUIT_REEXAM','ENV','재수 포기'),
 ('학원부적응','MALADJUST','ENV','학원 부적응'),
 ('타247이동','MOVE_247','ENV','타 247 이동'),
 ('기숙학원이동','MOVE_BOARDING','ENV','기숙학원 이동'),
 ('추가합격','ADMIT','PERSONAL','합격·진학'),
 ('수시합격','ADMIT','PERSONAL','합격·진학'),
 ('대학교합격','ADMIT','PERSONAL','합격·진학'),
 ('대학복학','ADMIT','PERSONAL','합격·진학'),
 ('가정형편','PERSONAL_FIN','PERSONAL','가정형편'),
 ('부모님반대','PERSONAL_OPP','PERSONAL','보호자 반대'),
 ('유학','ABROAD','ETC','유학'),
 ('급식문제','FACILITY','FACILITY','시설/급식')
on conflict (raw_text) do nothing;
-- 미매칭 표기는 reason_code='UNMAPPED' 으로 적재하여 격리(자동 추측 금지) → 운영자가 본 표에 추가.

-- 2) churn_reasons 보강 — 표준 코드·대분류·건수·시즌·출처
alter table churn_reasons add column if not exists reason_code text;
alter table churn_reasons add column if not exists major_code  text;
alter table churn_reasons add column if not exists cnt         int;
alter table churn_reasons add column if not exists season      text;   -- 'N수'|'정규'|'윈터'|'조기선발'|null(전체)
alter table churn_reasons add column if not exists source      text default 'erp';  -- 'sangdam'|'erp'

-- 3) 적재 예시 — 대치점, 상담일지 누적 1,297건 (파서 산출, scope='branch')
--    실적재 시 delete(해당 branch+source+season) 후 insert (멱등)
-- delete from churn_reasons where scope='branch' and source='sangdam' and branch_id = '<대치 branch_id>';
-- insert into churn_reasons(scope,branch_id,reason,reason_code,major_code,pct,cnt,rank,source) values
--  ('branch','<대치>','등원 전 환불','NO_SHOW_REFUND','ENV',49.7,645,1,'sangdam'),
--  ('branch','<대치>','타학원 이동','MOVE_OTHER_ACADEMY','ENV',15.2,197,2,'sangdam'),
--  ('branch','<대치>','독학 전환','SELF_STUDY','ENV',11.0,143,3,'sangdam'),
--  ('branch','<대치>','통학거리','DISTANCE','ENV',5.7,74,4,'sangdam'),
--  ('branch','<대치>','건강 악화','HEALTH','PERSONAL',3.9,51,5,'sangdam'),
--  ('branch','<대치>','재수 포기','QUIT_REEXAM','ENV',1.8,23,6,'sangdam'),
--  ('branch','<대치>','학원 부적응','MALADJUST','ENV',1.3,17,7,'sangdam'),
--  ('branch','<대치>','타 247 이동','MOVE_247','ENV',1.1,14,8,'sangdam');

alter table reason_code_map enable row level security;
do $$ begin create policy rcm_read on reason_code_map for select using (true); exception when duplicate_object then null; end $$;
