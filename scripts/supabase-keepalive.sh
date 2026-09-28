#!/usr/bin/env bash
# Supabase 무료 플랜 7일 미사용 자동정지 방지 + 정지·소실 조기경보 (실패 종료 → GitHub가 메일 발송)
# URL·anon 키는 app/config.js 에서 읽음 (공개값, 단일 출처). 사용: bash scripts/supabase-keepalive.sh
set -uo pipefail
cd "$(dirname "$0")/.."

url=$(grep -o 'SUPABASE_URL: *"[^"]*"' app/config.js | cut -d'"' -f2)
key=$(grep -o 'SUPABASE_ANON_KEY: *"[^"]*"' app/config.js | cut -d'"' -f2)
[ -n "$url" ] && [ -n "$key" ] || { echo "::error::app/config.js 에서 URL/키를 못 읽음"; exit 1; }
echo "대상: $url"

# 실제 DB 쿼리 1건 (Supabase가 '활동'으로 인정하는 것은 DB 요청 — 헬스체크만으론 부족)
# apikey 헤더만 사용 → 레거시 anon(JWT)·신규 publishable 키 모두 호환
code=$(curl -sS -o /tmp/ka_body.txt -w '%{http_code}' --max-time 30 \
  -H "apikey: $key" "$url/rest/v1/branches?select=id&limit=1" 2>/tmp/ka_err.txt)
rc=$?

if [ $rc -ne 0 ]; then
  echo "::error::연결 실패 (curl $rc: $(cat /tmp/ka_err.txt)) — 프로젝트가 정지·삭제됐을 가능성. 대시보드에서 Restore 확인 필요."
  exit 1
fi
if [ "$code" != "200" ]; then
  echo "::error::HTTP $code — 정상 응답 아님. 응답: $(head -c 300 /tmp/ka_body.txt)"
  exit 1
fi
echo "✅ 정상 (HTTP 200) — DB 활동 기록됨"
