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
