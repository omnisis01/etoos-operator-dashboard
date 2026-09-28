# 트리아지 어시스턴트 — 컨텍스트 노트 (결정·이유)

## 아키텍처
- 정적 프론트(GitHub Pages) + Supabase. **정적 사이트는 Claude API 키를 담을 수 없으므로** 얇은 백엔드가 필요 → Supabase Edge Function(Deno)에 프록시. 키는 서버에만 격리(하네스 원칙: 모델은 제안, 하네스가 키·권한·예산 통제).
- Edge Function 엔드포인트: `https://oquuwouxgiskxgawjyjv.supabase.co/functions/v1/triage`
- 프론트는 `sb.functions.invoke('triage', {body:{items,branch}})` 로 호출 → supabase-js가 로그인 세션 JWT를 자동 첨부.

## 하네스 결정 (연구한 원칙 적용)
- **키 격리**: `Deno.env.get('ANTHROPIC_API_KEY')`. 커밋 금지, 시크릿으로만.
- **스키마 검증(결정적)**: `output_config.format`(json_schema)로 모델 출력이 반드시 스키마를 따르게 강제. 프롬프트로 "JSON 주세요"가 아니라 API가 보증.
- **최소권한/과도한 권한 차단**: JWT role이 `authenticated`가 아니면 401 (공개 anon 키만으로는 호출 불가). 데모(mock)는 실 API를 안 쓰므로 호출 불가 — 데모는 별도의 정적 예시로 처리(실데이터 노출 방지 원칙과 일치).
- **예산 상한**: max_tokens=2000, 입력 항목 ≤ 20. 응답에 usage 반환(관측성).
- **부작용 없음(1단계)**: 이 함수는 읽기·제안만. 문자/DB 변경은 3단계에서 사람 승인 후.

## 모델
- `claude-opus-4-8` (스킬 기본값). 비용: 입력 $5 / 출력 $25 per 1M. 트리아지 1회 ≈ 입력 수백~1천 토큰 + 출력 수백 토큰 → 회당 대략 1~2센트대. 저렴하게 가려면 `claude-haiku-4-5`($1/$5) 또는 `claude-sonnet-5`로 교체 가능(모델 문자열만 변경). 다운그레이드는 원장님 결정 사항이라 기본은 opus 유지.
- 사고: `thinking:{type:'adaptive'}` + `output_config.effort:'medium'` (우선순위 판단에 약간의 추론 필요, 지연은 수 초).

## 배포에 필요한 것 (원장님 몫 — 내가 대신 못 함)
1. supabase CLI 설치 (`brew install supabase/tap/supabase`)
2. `supabase login` → `supabase link --project-ref oquuwouxgiskxgawjyjv`
3. `supabase secrets set ANTHROPIC_API_KEY=sk-ant-...`  ← Anthropic 콘솔에서 발급한 키
4. `supabase functions deploy triage`
- **주의**: API 키는 절대 config.js/코드/깃에 넣지 않는다. 오직 supabase secrets.

## 검증 한계 (솔직히)
- 이 세션에서는 supabase CLI·API 키·프로젝트 로그인이 없어 라이브 호출 검증 불가. 코드 정합성까지만 확인, 실제 동작 확인은 배포 후 원장님 환경에서.

## 2026-07-03 — 밴드 병합 + 계정 4층위 구조화
- 즉시 확인 독립 카드 삭제 → '지점 할일' 카드 상단으로 병합. 즉시확인(riskBody)과 오늘의 할일(todoBody) 사이는 실선 한 줄(.imm-divider)로만 구분. 트리아지 버튼·결과 박스도 지점 할일 카드로 이동. 밴드는 다시 1행 2단(local | hq).
- 계정 층위 확정: (1) exec 대표·임원 = (2) hq_staff 본사 담당 > (3) director 지점 원장 > (4) staff 지점 직원.
  · '=' 의미 = 조회 범위(전사) 동급, 관리 권한(manage)은 exec 전용.
  · staff는 매출·미수금 차단(sales:false) — 설문(은평서대문)의 직원 노출 우려 대응 기반.
  · 프론트: lib/auth.js ROLES/roleInfo()/can() · DB: db/roles.sql (enum 확장 + role_rank + is_hq/can_view_sales, 기존 is_exec() 정책 호환 재정의). 미지정 role은 최소권한(staff) 폴백.

## 2026-07-03 — 본사 알림장 대표이사 피드백 반영 (전부 수용)
- 5개 카테고리 그룹 구조로 개편: ①본사 마케팅 키워드 ②지점 분석 마케팅 키워드 ③본사 진행 마케팅 활동 ④본사 지원·협업 ⑤이투스 닷컴 지원·협업.
- 키워드 그룹(①②)은 버튼 없는 안내 노트형(ⓘ 골드), 활동 그룹(③④⑤)은 신청/참여 버튼(목업).
- 교재 지원은 이지영·김민정 400부 → 정승제 100부로 교체(대표 표기준).
- 데이터 구조 HQ_GROUPS — 실연동 시 hq_notes 테이블에 grp 컬럼 추가하면 됨.

## 2026-09-28 — Supabase 프로젝트 소실 및 복구 준비
- 증상: 원장님 Supabase 계정에서 프로젝트가 안 보임. `oquuwouxgiskxgawjyjv.supabase.co` DNS가 NXDOMAIN → 프로젝트 삭제/회수(무료 플랜 장기 미사용 추정, 마지막 연동 6월 중순).
- 계정 추정: 모든 커밋 작성자 `omnisis01@gmail.com`, DEPLOY.md가 "GitHub 계정으로 가입" 안내 → GitHub OAuth 로그인 가능성 높음. 비밀번호는 원래부터 저장소에 없음(의도된 보안 규칙).
- 데모(/demo/)는 Supabase 미사용 목업이라 영향 없음.
- **발견한 버그**: roles.sql 을 SQL Editor에서 한 번에 RUN하면 실패. PostgreSQL은 다중문 쿼리를 단일 트랜잭션으로 실행하는데, 같은 트랜잭션에서 방금 ADD VALUE 한 enum 값('hq_staff')을 함수 본문이 쓰면 "unsafe use of new value" 에러. 7월 작성 당시 실DB에 돌려본 적 없어 숨어 있었음.
- 해결: enum 추가 2줄을 번들 1 끝에 넣어 커밋 → 번들 2에서 함수 생성. roles.sql 원본엔 주의문만 추가(원본 내용 유지).
- 번들 순서 = git 추가 순서(의존 순서). 전부 `if not exists` 멱등이고 SQL Editor가 한 트랜잭션으로 돌리므로 중간 실패 시 전체 롤백 → 재실행 안전. (seed.sql은 insert 10개 중 on conflict 5개라 부분 적용 상태의 재실행은 위험하지만, 트랜잭션 롤백 덕에 그 상황이 안 생김)
- 검증 방법: PGlite(WASM PostgreSQL)에 Supabase 기본값(auth 스키마·auth.uid()·authenticated 역할·기본 권한)을 흉내 내고 실행. 첫 RLS 실패는 번들 문제가 아니라 테스트 환경에 Supabase 기본 권한을 안 넣은 탓 → 테스트 환경만 보강, 번들은 불변.
- 실데이터(재원생·미수금·출결 등)는 옛 DB와 함께 소실. 원본 파일 재적재 필요.

## 2026-09-28 — [정정 + 원인 확정] Supabase 사고 분석 (위 "소실" 판단은 성급했음)
### 정정
- 위 항목에서 NXDOMAIN만 보고 "삭제·소실"로 단정했으나 **틀렸음**. Gmail 증거상 **삭제가 아니라 일시정지**.
- 정지 중엔 컴퓨트가 내려가 도메인이 조회되지 않을 수 있음 → NXDOMAIN 자체는 삭제 증거가 아니었음.

### 증거
- 2026-08-28 02:07 UTC, `ant.wilson@supabase.com` → `omnisis01@gmail.com`
  "Your Supabase Project omnisis01's Project has been paused." (ID: oquuwouxgiskxgawjyjv, 사유: 7일 미사용)
- 해당 메일 상태: **읽지 않음 + 휴지통**. 정지 1주 전 경고 메일·삭제 메일은 검색되지 않음(in:anywhere).
- Supabase 정책(공식 문서): 무료 플랜은 지난 1주간 DB 활동이 부족하면 정지 / 정지 후 **1년 내 Restore 가능** / 무료 플랜 백업 보존 0일.
- 코드: `?mock=1`·`/demo/` 경로는 `window.sb = null` → Supabase를 전혀 호출하지 않음.

### 타임라인
- 06-13~06-24 실DB 구축·실데이터 적재 (활발한 DB 사용)
- 07-03 DB 관련 마지막 변경(roles.sql 작성 — 실DB엔 미실행)
- 07-09 `/demo/` 도입 → 07-09~07-15 가맹원장 39명 설문이 전부 데모로 진행 (DB 호출 0)
- ~08-21 마지막 DB 활동 추정 → 08-28 자동 정지 → 알림 메일 미확인·휴지통
- 09-28 발견 (정지 31일째, 복구 가능 기한 2027-10-02 — 대시보드 표기로 확정. 이후엔 재개 불가, 데이터 다운로드만 가능)

### 근본 원인 (5 Whys)
1. 직접 원인: 무료 플랜 7일 미사용 자동정지.
2. 왜 사용이 없었나 → **실데이터를 보호하려고 만든 데모 모드가 모든 외부 트래픽을 흡수**. 공유·설문·시연이 전부 DB를 안 부르는 경로로 갔고, 실서비스 로그인은 정기 사용자가 없었음. 안전장치가 DB를 굶긴 구조.
3. 왜 몰랐나 → 정지 알림이 **휴지통**으로 감. 프로젝트에 가동 감시가 **전혀 없었음**. 사이트(데모)는 계속 정상이라 겉으론 아무 이상 없어 보임.
4. 왜 위험했나 → 무료 플랜 **백업 없음** + 별도 백업도 안 만듦 → 가공된 실데이터의 유일한 사본이 정지된 DB에만 있음.
5. 왜 찾기 어려웠나 → 프로젝트 이름이 기본값 `omnisis01's Project`(DEPLOY.md 지시는 `etoos-operator`), 소유 계정·ID가 문서 어디에도 없음. 그리고 내가 증거 확인 전에 "삭제"로 단정해 판단을 흐림.

### 재발방지책
- [적용] `scripts/supabase-keepalive.sh` + `.github/workflows/supabase-keepalive.yml` — 하루 2회 실DB 쿼리로 정지 방지, 정지·소실·키오류 시 워크플로 실패 → GitHub 메일 경보. 로컬 테스트: 연결실패(curl 6)·HTTP 401 두 경보 경로 모두 exit 1 확인. 정상(200) 경로는 복구 후 확인 예정.
  - 한계: 공개 저장소는 60일간 저장소 활동이 없으면 예약 워크플로가 자동 비활성화됨(GitHub 정책). 비활성화 전 GitHub가 메일로 알림 → 그 메일도 놓치면 안 됨. 근본 해결은 Pro 전환.
- [적용] DEPLOY.md 상단에 소유 계정·프로젝트 이름·ID·요금제 정책·복구 기한 기록(비밀번호 제외).
- [원장님 조치] Gmail 필터: `from:supabase.com` → 중요 표시 + 휴지통 금지 라벨. (계정 설정 변경이라 직접 해야 함)
- [원장님 결정] 백업: ① 정식 출시 시 Pro($25/월, 정지 없음 + 일일 백업) 권장 ② 또는 주기적 pg_dump — 단 저장소가 **공개**라 GitHub 아티팩트에 개인정보 백업을 올리면 안 됨(암호화 필수) ③ 또는 원장님 Mac 로컬 백업.
- [원칙] 실데이터 원본 파일(미수금 xls·상담일지 xlsb 등)은 고정 폴더에 보관 → 언제든 재적재 가능하게.
- [원칙] "사라졌다" 판단 전에 소유자 알림 메일·공식 정책부터 확인. 추정으로 단정 금지.
