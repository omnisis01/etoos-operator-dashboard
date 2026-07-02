// 지점 '즉시 확인' 항목을 우선순위로 정리하는 Claude 프록시 (Supabase Edge Function, Deno)
import Anthropic from "npm:@anthropic-ai/sdk";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

// 모델 출력이 반드시 이 형태를 따르도록 강제 (하네스가 스키마 검증)
const SCHEMA = {
  type: "object",
  additionalProperties: false,
  properties: {
    summary: { type: "string" },
    items: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        properties: {
          label: { type: "string" },
          priority: { type: "integer" },
          urgency: { type: "string", enum: ["긴급", "주의", "보통"] },
          action: { type: "string" },
          reason: { type: "string" },
        },
        required: ["label", "priority", "urgency", "action", "reason"],
      },
    },
  },
  required: ["summary", "items"],
};

const SYSTEM =
  "당신은 이투스247 지점 운영 보조입니다. 지점의 '즉시 확인' 항목을 위급도 순으로 정리하고, " +
  "각 항목에 권장 다음 액션과 근거를 제안합니다. 당신은 제안만 하며 문자 발송·DB 변경 등 실제 행동은 하지 않습니다. " +
  "한국어로 답하고, 모든 문장은 마침표로 끝냅니다. priority 는 1이 최우선입니다.";

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "POST only" }, 405);

  // 최소권한: 로그인 사용자만 (공개 anon 키만으로는 차단). JWT는 Supabase가 이미 서명 검증함.
  const role = decodeRole(req.headers.get("Authorization") ?? "");
  if (role !== "authenticated") return json({ error: "login required" }, 401);

  const key = Deno.env.get("ANTHROPIC_API_KEY");
  if (!key) return json({ error: "server not configured (ANTHROPIC_API_KEY missing)" }, 500);

  let body: any;
  try { body = await req.json(); } catch { return json({ error: "invalid json" }, 400); }

  const items = Array.isArray(body?.items) ? body.items : [];
  if (items.length === 0) return json({ error: "items required" }, 400);
  if (items.length > 20) return json({ error: "too many items (max 20)" }, 400);   // 예산 상한

  const branch = typeof body?.branch === "string" ? body.branch : "우리 지점";
  const list = items
    .map((it: any, i: number) => `${i + 1}. ${it.label ?? ""} — ${it.value ?? ""} (${it.sub ?? ""})`)
    .join("\n");

  const client = new Anthropic({ apiKey: key });
  try {
    const res = await client.messages.create({
      model: "claude-opus-4-8",
      max_tokens: 2000,
      thinking: { type: "adaptive" },
      output_config: { effort: "medium", format: { type: "json_schema", schema: SCHEMA } },
      system: SYSTEM,
      messages: [
        { role: "user", content: `${branch}의 오늘 즉시 확인 항목입니다. 우선순위로 정리해 주세요.\n\n${list}` },
      ],
    });
    const text = res.content
      .filter((b: any) => b.type === "text")
      .map((b: any) => b.text)
      .join("");
    let triage: unknown;
    try { triage = JSON.parse(text); } catch { return json({ error: "model output parse failed", raw: text }, 502); }
    return json({ ok: true, triage, usage: res.usage });
  } catch (e: any) {
    return json({ error: "claude request failed", detail: String(e?.message ?? e) }, 502);
  }
});

// 이미 서명 검증된 JWT에서 role 클레임만 추출 (검증이 아니라 게이팅 용도)
function decodeRole(authz: string): string | null {
  const jwt = authz.replace(/^Bearer\s+/i, "").trim();
  const seg = jwt.split(".")[1];
  if (!seg) return null;
  try {
    const pad = seg.replace(/-/g, "+").replace(/_/g, "/");
    const payload = JSON.parse(atob(pad + "=".repeat((4 - (pad.length % 4)) % 4)));
    return typeof payload?.role === "string" ? payload.role : null;
  } catch { return null; }
}

function json(obj: unknown, status = 200): Response {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { ...CORS, "content-type": "application/json" },
  });
}
