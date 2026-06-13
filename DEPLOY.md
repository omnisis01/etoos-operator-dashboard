# 운영자 대시보드 — 배포 & DB 구축 가이드

현재 산출물: `운영자 대시보드_v3_라이트다크.html` (정적 프로토타입, 더미 데이터)
목표: **DB에 데이터 저장 → API 조회 → 공개 URL 배포**

권장 스택: **Supabase(Postgres + 인증 + 자동 API) + 정적/Next.js 프런트 + Vercel**
무료 티어로 시작 가능하며, 원장/임원 역할 분리(RLS)가 내장됩니다.

---

## 전체 단계 (체크리스트)

- [x] **1. DB 스키마 설계** — `db/schema.sql`
- [x] **2. 샘플 데이터** — `db/seed.sql`
- [ ] **3. Supabase 프로젝트 생성** ← *사장님 계정 필요 (아래 3단계)*
- [ ] **4. 스키마 + 시드 실행**
- [ ] **5. 프런트엔드를 DB에 연결** (Claude가 작업)
- [ ] **6. 인증/로그인 추가** (원장/임원)
- [ ] **7. Vercel 배포**
- [ ] **8. (추후) MY247·LMS·ERP 실데이터 연동**

---

## 3. Supabase 프로젝트 생성 (약 3분)

1. https://supabase.com 가입 (GitHub 계정으로 간편)
2. **New Project** → 이름 `etoos-operator`, 비밀번호 설정, Region = **Northeast Asia (Seoul)**
3. 생성 후 **Project Settings → API** 에서 아래 2개를 복사해 두기:
   - `Project URL`  (예: `https://xxxx.supabase.co`)
   - `anon public` 키

> 이 두 값을 알려주시면 5단계(프런트 연결)를 바로 진행합니다.
> ⚠️ `service_role` 키는 절대 공유·노출하지 마세요. 프런트엔드엔 `anon` 키만 사용합니다.

## 4. 스키마 + 시드 실행

Supabase 대시보드 → **SQL Editor** → New query 에:
1. `db/schema.sql` 전체 붙여넣기 → **RUN**
2. `db/seed.sql` 전체 붙여넣기 → **RUN**

→ **Table Editor** 에서 `branches`, `students`, `metrics_snapshot` 등에 데이터가 들어왔는지 확인.

## 5. 프런트엔드 → DB 연결 (Claude 작업)

`anon` 키를 받으면:
- 대시보드의 하드코딩 수치를 Supabase 조회로 교체
- KPI/차트/명단이 `metrics_snapshot`, `daily_metrics`, `churn_risks`, `payments`, `churn_reasons` 에서 로드
- Supabase JS 클라이언트(`@supabase/supabase-js`) 사용

## 6. 인증 (원장/임원)

- Supabase **Authentication → Users** 에서 운영자 계정 생성
- `profiles` 테이블에 `role`(exec/director)·`branch_id` 지정
- RLS가 자동 적용 → 원장은 자기 지점만, 임원은 전사 조회

## 7. Vercel 배포

- GitHub 저장소에 코드 push
- https://vercel.com → Import → 환경변수에 `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY` 입력
- Deploy → 공개 URL 발급

## 8. 실데이터 연동 (추후)

- MY247·LMS·ERP의 API 또는 DB 접근 정보 확보 후
- Supabase **Edge Function** 또는 별도 ETL로 주기적 동기화 → `daily_metrics`·`churn_risks` 등 갱신
- 또는 운영자가 CSV 업로드 → 적재하는 화면 추가

---

## 데이터 모델 요약

| 테이블 | 용도 | 대시보드 매핑 |
|---|---|---|
| `branches` | 지점 마스터 | 전사 테이블·권역 |
| `metrics_snapshot` | 지점 헤드라인 1행 | 상단 KPI·재원생·출결 카드 |
| `students` | 재원생 | 명단의 기준 |
| `attendance` | 출결 이력 | 출결 현황 |
| `payments` | 수납/미납 | 미납·결제 관리 |
| `consultations` | 상담 기록 | 상담 AI 분석 |
| `churn_risks` | AI 퇴원 위험 | 퇴원 위험 감지 |
| `daily_metrics` | 월별 집계 | 라인·영역·바 차트 |
| `churn_reasons` | 이탈 사유 | 도넛 차트 |
| `action_items` | 할 일 | 액션 플랜 |
| `profiles` | 운영자·역할 | 로그인/권한(RLS) |
