export type TtsGear = "slow" | "normal" | "fast";

/** MiniMax speed per gear. `normal` matches the app review pace (0.7). */
export const gearSpeeds: Record<TtsGear, number> = {
  slow: 0.5,
  normal: 0.7,
  fast: 1.0,
};

export function parseGear(value: unknown): TtsGear {
  if (value === "slow" || value === "normal" || value === "fast") {
    return value;
  }
  return "normal";
}

/**
 * Must stay identical to Dart `sanitizeSpeakText`
 * (lib/core/audio/device_tts_service.dart): blanks/ellipsis collapsed,
 * runs of underscores and whitespace collapsed, then trimmed.
 */
export function normalizeText(text: string): string {
  return text
    .replaceAll("___", " ")
    .replaceAll("__", " ")
    .replaceAll("……", " ")
    .replaceAll("…", " ")
    .replace(/_+/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

export async function sha256Hex(input: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(input),
  );
  return [...new Uint8Array(digest)]
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

/**
 * Cache key contract (mirrored in docs + Dart `ttsCacheKey` test helper):
 * `tts/v1/{modelVersion}/{voiceSlug}/{gear}/{sha256(normalize(text))}.mp3`
 *
 * The slug (not the raw voice id) goes into the key because voice ids
 * contain URL-unsafe characters: fullwidth parens in the Mary voice,
 * spaces/parens in the waiter voice. Raw ids broke playback URLs.
 */
export async function buildCacheKey(args: {
  modelVersion: string;
  voiceId: string;
  gear: TtsGear;
  text: string;
}): Promise<string> {
  const hash = await sha256Hex(normalizeText(args.text));
  const slug = await voiceSlug(args.voiceId);
  return `tts/v1/${args.modelVersion}/${slug}/${args.gear}/${hash}.mp3`;
}

/** URL-safe aliases for known voices; unknown ids hash to `v-<12hex>`. */
const knownVoiceSlugs: Record<string, string> = {
  Cantonese_GentleLady: "gentle",
  "Cantonese_ProfessionalHost（F)": "mary",
  Cantonese_Articulate_commentator_vv2: "peter",
  "Chinese (Mandarin)_HK_Flight_Attendant": "waiter",
};

export async function voiceSlug(voiceId: string): Promise<string> {
  const known = knownVoiceSlugs[voiceId];
  if (known) return known;
  const hash = await sha256Hex(voiceId);
  return `v-${hash.slice(0, 12)}`;
}

export function resolveVoice(
  requested: unknown,
  allowed: string[],
  fallback: string,
): string {
  const voice =
    typeof requested === "string" && requested.trim().length > 0
      ? requested.trim()
      : fallback;
  return allowed.includes(voice) ? voice : fallback;
}
