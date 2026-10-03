/**
 * Best-effort per-IP sliding-window limiter kept in Worker memory.
 * MVP scope only: stops casual abuse of the MiniMax bill. For strict
 * distributed limiting, add a Cloudflare Rate Limiting rule in front of
 * the Worker (see README) — the 429 contract below stays the same.
 */
const hits = new Map<string, number[]>();

export function isRateLimited(
  ip: string,
  nowMs: number,
  limitPerMin: number,
): boolean {
  const windowStart = nowMs - 60_000;
  const bucket = hits.get(ip) ?? [];
  const recent = bucket.filter((t) => t > windowStart);
  recent.push(nowMs);
  // Bound memory: keep only the current window.
  hits.set(ip, recent.slice(-Math.max(limitPerMin, 1) * 2));
  return recent.length > limitPerMin;
}
