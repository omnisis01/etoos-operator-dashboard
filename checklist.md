# 즉시확인 트리아지 어시스턴트 — 체크리스트

프론트 표기는 쉬운 한글("우선순위 정리 도우미"). 4단계 = 가장 작은 스택부터.

## 1단계 — 백엔드 최소 하네스 (보류 — 비용/모델 결정 대기)
> 코드는 커밋됨(supabase/functions/triage/index.ts)이나 미배포 상태 = 라이브 앱에 영향 없음.
> 재개 시 결정할 것: (a) Haiku API 공용 배포  vs  (b) Ollama 로컬 전용. API 경로면 크레딧 필요.

- [x] Supabase 프로젝트 확인 (ref: oquuwouxgiskxgawjyjv)
- [x] Edge Function 작성 `supabase/functions/triage/index.ts` (Claude 프록시)
  - [x] 키 격리 — `ANTHROPIC_API_KEY` 를 Deno 환경변수(시크릿)에서만 읽음
  - [x] 스키마 검증 — `output_config.format`(json_schema)로 구조화 출력 강제
  - [x] 예산 상한 — max_tokens 2000, 입력 항목 ≤ 20, 로그인 사용자만(anon 차단)
- [ ] **(원장님)** supabase CLI 설치 → `supabase link` → 시크릿 등록 → `functions deploy triage`
- [ ] verify: 더미 입력으로 구조화 출력(JSON) 반환 확인

## 2단계 — 읽기 전용 트리아지 (목업으로 완료 ✅)
- [x] 즉시 확인 카드에 "✦ 우선순위 정리" 버튼
- [x] `triage()` 이음새 + 목업 어댑터(triageMock) → 순위 카드 렌더 (모델 호출 0)
- [x] verify: 프리뷰에서 3항목 우선순위·액션·근거 카드 표시, DB/발송 0, 콘솔 오류 0
- [ ] (출시 시) triage() 목업 → 실 어댑터(sb.functions.invoke) 한 줄 교체 + Edge Function 배포

## 3단계 — 초안 + 승인 루프 (목업으로 완료 ✅)
- [x] 순위 카드별 "✉ 초안" → 문자 초안 생성(draftFor 이음새, 템플릿 목업)
- [x] 문안 수정 가능(textarea), "승인하고 발송(목업)" 눌러야만 발송 처리
- [x] verify: 네트워크 요청 정적 자원뿐 — 발송·API 호출 0, 콘솔 오류 0

## 4단계 — 스킬 축적 (목업으로 완료 ✅)
- [x] 승인된 문구를 스킬로 저장(localStorage triSkills, 항목 라벨 키)
- [x] 다음 초안에서 저장 문구 자동 재사용 + "저장된 문구 재사용" 배지
- [x] verify: 수정→승인→재오픈 시 수정 문구 그대로 재사용 확인
- [ ] (출시 시) draftFor()도 실 어댑터로 교체, 스킬 저장을 DB(지점별)로 이전
