import { authenticate } from "./auth";
import { buildCacheKey, gearSpeeds, normalizeText, parseGear, resolveVoice } from "./cacheKey";
import { MinimaxError, synthesizeMp3 } from "./minimax";
import { isRateLimited } from "./ratelimit";

interface Env {
  TTS_AUDIO: R2Bucket;
  MINIMAX_API_KEY: string;
  MINIMAX_BASE_URL: string;
  MINIMAX_MODEL: string;
  MODEL_VERSION: string;
  DEFAULT_VOICE_ID: string;
  LANGUAGE_BOOST: string;
  ALLOWED_VOICES: string;
  MAX_TEXT_LENGTH: string;
  MAX_BATCH_ITEMS: string;
  RATE_LIMIT_PER_MIN: string;
}

const audioHeaders = {
  "Content-Type": "audio/mpeg",
  "Cache-Control": "public, max-age=31536000, immutable",
};

function corsHeaders(): Record<string, string> {
  return {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type, Authorization",
    "Access-Control-Max-Age": "86400",
  };
}

function json(data: unknown, status = 200, extra?: Record<string, string>): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      "Content-Type": "application/json",
      ...corsHeaders(),
      ...extra,
    },
  });
}

function error(message: string, status: number): Response {
  return json({ error: message }, status);
}

function clientIp(request: Request): string {
  return (
    request.headers.get("CF-Connecting-IP") ??
    request.headers.get("X-Forwarded-For")?.split(",")[0]?.trim() ??
    "unknown"
  );
}

interface ResolvedItem {
  key: string;
  voiceId: string;
  gear: "slow" | "normal" | "fast";
  text: string;
}

/** Shared validation so single + batch stay consistent. */
function resolveItem(
  raw: { text?: unknown; voiceId?: unknown },
  gearRaw: unknown,
  env: Env,
): ResolvedItem | { error: string } {
  const normalized =
    typeof raw.text === "string" ? normalizeText(raw.text) : "";
  if (normalized.length === 0) {
    return { error: "empty text" };
  }
  const maxLength = Number(env.MAX_TEXT_LENGTH || "200");
  if (normalized.length > maxLength) {
    return { error: `text too long (max ${maxLength} chars)` };
  }
  const allowed = (env.ALLOWED_VOICES || "")
    .split(",")
    .map((v) => v.trim())
    .filter((v) => v.length > 0);
  const voiceId = resolveVoice(raw.voiceId, allowed, env.DEFAULT_VOICE_ID);
  return { text: normalized, voiceId, gear: parseGear(gearRaw) } as ResolvedItem;
}

async function synthesizeAndStore(
  item: ResolvedItem,
  env: Env,
): Promise<{ key: string }> {
  const key = await buildCacheKey({
    modelVersion: env.MODEL_VERSION,
    voiceId: item.voiceId,
    gear: item.gear,
    text: item.text,
  });
  // Best-effort single-flight: concurrent MISS for the same key simply
  // last-write-wins with identical bytes, so no lock is needed for MVP.
  const existing = await env.TTS_AUDIO.head(key);
  if (existing) {
    return { key };
  }
  if (!env.MINIMAX_API_KEY) {
    throw new MinimaxError("server missing MINIMAX_API_KEY", false);
  }
  const mp3 = await synthesizeMp3({
    apiKey: env.MINIMAX_API_KEY,
    baseUrl: env.MINIMAX_BASE_URL,
    model: env.MINIMAX_MODEL,
    languageBoost: env.LANGUAGE_BOOST,
    voiceId: item.voiceId,
    speed: gearSpeeds[item.gear],
    text: item.text,
  });
  // R2Bucket.put accepts Uint8Array via ArrayBuffer view; copy for safety.
  await env.TTS_AUDIO.put(key, mp3.slice().buffer as ArrayBuffer, {
    httpMetadata: { contentType: "audio/mpeg", cacheControl: audioHeaders["Cache-Control"] },
  });
  return { key };
}

function audioUrl(request: Request, key: string): string {
  return `${new URL(request.url).origin}/a/${key}`;
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: corsHeaders() });
    }

    if (request.method === "GET" && url.pathname === "/health") {
      return json({ ok: true });
    }

    if (request.method === "GET" && url.pathname.startsWith("/a/")) {
      const key = url.pathname.slice("/a/".length);
      if (!key || key.includes("..")) {
        return error("not found", 404);
      }
      const object = await env.TTS_AUDIO.get(key);
      if (!object) {
        return error("not found", 404);
      }
      return new Response(object.body, {
        headers: {
          ...audioHeaders,
          ...corsHeaders(),
          ETag: object.httpEtag,
          "X-Cache": "HIT",
        },
      });
    }

    if (request.method === "POST" && url.pathname === "/v1/tts") {
      return handleSingle(request, env);
    }

    if (request.method === "POST" && url.pathname === "/v1/tts/batch") {
      return handleBatch(request, env);
    }

    return error("not found", 404);
  },
};

async function gate(request: Request, env: Env): Promise<Response | null> {
  const auth = await authenticate(request);
  if (!auth.allow) {
    return error("unauthorized", 401);
  }
  const limit = Number(env.RATE_LIMIT_PER_MIN || "60");
  if (isRateLimited(clientIp(request), Date.now(), limit)) {
    return error("rate limited, slow down", 429);
  }
  return null;
}

async function handleSingle(request: Request, env: Env): Promise<Response> {
  const blocked = await gate(request, env);
  if (blocked) return blocked;

  let body: { text?: unknown; voiceId?: unknown; gear?: unknown };
  try {
    body = (await request.json()) as typeof body;
  } catch {
    return error("invalid JSON", 400);
  }
  const resolved = resolveItem(body, body.gear, env);
  if ("error" in resolved) {
    return error(resolved.error, 400);
  }
  try {
    const before = await env.TTS_AUDIO.head(
      await buildCacheKey({
        modelVersion: env.MODEL_VERSION,
        voiceId: resolved.voiceId,
        gear: resolved.gear,
        text: resolved.text,
      }),
    );
    const { key } = await synthesizeAndStore(resolved, env);
    return json(
      { url: audioUrl(request, key), cache: before ? "HIT" : "MISS", gear: resolved.gear },
      200,
      { "X-Cache": before ? "HIT" : "MISS" },
    );
  } catch (e) {
    return upstreamError(e);
  }
}

async function handleBatch(request: Request, env: Env): Promise<Response> {
  const blocked = await gate(request, env);
  if (blocked) return blocked;

  let body: { items?: unknown; gear?: unknown };
  try {
    body = (await request.json()) as typeof body;
  } catch {
    return error("invalid JSON", 400);
  }
  if (!Array.isArray(body.items)) {
    return error("items must be an array", 400);
  }
  const maxItems = Number(env.MAX_BATCH_ITEMS || "20");
  if (body.items.length === 0 || body.items.length > maxItems) {
    return error(`items must have 1-${maxItems} entries`, 400);
  }
  const resolved: ResolvedItem[] = [];
  for (const raw of body.items as { text?: unknown; voiceId?: unknown }[]) {
    const item = resolveItem(raw ?? {}, body.gear, env);
    if ("error" in item) {
      return error(`invalid item: ${item.error}`, 400);
    }
    resolved.push(item);
  }
  try {
    const urls: string[] = [];
    let hits = 0;
    // Sequential keeps MiniMax bursts bounded; R2 hits are cheap anyway.
    // All-items-identical batches still benefit from the per-key HEAD.
    for (const item of resolved) {
      const key = await buildCacheKey({
        modelVersion: env.MODEL_VERSION,
        voiceId: item.voiceId,
        gear: item.gear,
        text: item.text,
      });
      const before = await env.TTS_AUDIO.head(key);
      if (before) hits++;
      const stored = await synthesizeAndStore(item, env);
      urls.push(audioUrl(request, stored.key));
    }
    return json({ urls, cacheHits: hits, gear: resolved[0]?.gear ?? "normal" });
  } catch (e) {
    return upstreamError(e);
  }
}

function upstreamError(e: unknown): Response {
  if (e instanceof MinimaxError && !e.retryable) {
    return error(e.message, 502);
  }
  return error(e instanceof Error ? e.message : "tts failed", 502);
}
