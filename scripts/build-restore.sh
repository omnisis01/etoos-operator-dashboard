#!/usr/bin/env bash
# Supabase 새 프로젝트 복구용 — db/*.sql 을 실행 순서대로 묶어 붙여넣기용 SQL 2개를 생성
# 사용: bash scripts/build-restore.sh   → db/restore/1_tables_and_data.sql, 2_roles.sql
set -euo pipefail
cd "$(dirname "$0")/.."
out=db/restore; mkdir -p "$out"

# 의존 순서 (git 추가 순서 = 의존 순서, 전부 if not exists 로 멱등)
ORDER=(schema seed hq upload unpaid_data withdrawals sales_consult attendance churn churn_outcomes withdrawal_reasons)

f1="$out/1_tables_and_data.sql"
{
  echo "-- 복구 1/2 — 테이블·기본데이터·권한 enum (자동 생성: scripts/build-restore.sh, 직접 수정 금지)"
  for n in "${ORDER[@]}"; do
    printf '\n-- ================= db/%s.sql =================\n' "$n"
    cat "db/$n.sql"
  done
  # enum 값 추가는 여기서 커밋 → 2번에서 함수가 안전하게 사용 (같은 트랜잭션 사용 금지 회피)
  printf '\n-- ================= db/roles.sql (enum 추가분) =================\n'
  grep -E '^alter type user_role add value' db/roles.sql
} > "$f1"

f2="$out/2_roles.sql"
{
  echo "-- 복구 2/2 — 4층위 권한 함수 (1번 RUN 완료 후 실행, 자동 생성: scripts/build-restore.sh)"
  grep -vE '^alter type user_role add value' db/roles.sql
} > "$f2"

echo "생성: $f1 ($(wc -l < "$f1" | tr -d ' ')줄)"
echo "생성: $f2 ($(wc -l < "$f2" | tr -d ' ')줄)"
