export class MinimaxError extends Error {
  readonly retryable: boolean;

  constructor(message: string, retryable = true) {
    super(message);
    this.retryable = retryable;
  }
}

/** MiniMax auth failures must not be retried by callers. */
const authStatusCodes = new Set([1004, 1008, 2049]);

export interface SynthesizeArgs {
  apiKey: string;
  baseUrl: string;
  model: string;
  languageBoost: string;
  voiceId: string;
  speed: number;
  text: string;
}

/** Calls MiniMax sync TTS and returns raw mp3 bytes (hex-decoded). */
export async function synthesizeMp3(args: SynthesizeArgs): Promise<Uint8Array> {
  const root = args.baseUrl.endsWith("/")
    ? args.baseUrl.slice(0, -1)
    : args.baseUrl;
  const response = await fetch(`${root}/v1/t2a_v2`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${args.apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: args.model,
      text: args.text,
      stream: false,
      language_boost: args.languageBoost,
      voice_setting: { voice_id: args.voiceId, speed: args.speed, vol: 1, pitch: 0 },
      audio_setting: { sample_rate: 32000, bitrate: 128000, format: "mp3", channel: 1 },
    }),
  });

  if (response.status === 401 || response.status === 403) {
    throw new MinimaxError("MiniMax key rejected", false);
  }
  if (!response.ok) {
    throw new MinimaxError(`MiniMax request failed (${response.status})`);
  }

  const decoded = (await response.json()) as {
    base_resp?: { status_code?: number; status_msg?: string };
    data?: { audio?: unknown };
  };
  const base = decoded.base_resp;
  if (base && (base.status_code ?? 0) !== 0) {
    const code = base.status_code;
    const retryable = typeof code !== "number" || !authStatusCodes.has(code);
    throw new MinimaxError(`MiniMax: ${base.status_msg ?? code}`, retryable);
  }
  const audio = decoded.data?.audio;
  if (typeof audio !== "string" || audio.length === 0) {
    throw new MinimaxError("MiniMax returned no audio");
  }
  return decodeHex(audio);
}

function decodeHex(audio: string): Uint8Array {
  const cleaned = audio.trim();
  if (cleaned.length === 0 || cleaned.length % 2 !== 0) {
    throw new MinimaxError("MiniMax audio unparseable");
  }
  const bytes = new Uint8Array(cleaned.length / 2);
  for (let i = 0; i < bytes.length; i++) {
    const byte = parseInt(cleaned.slice(i * 2, i * 2 + 2), 16);
    if (Number.isNaN(byte)) {
      throw new MinimaxError("MiniMax audio unparseable");
    }
    bytes[i] = byte;
  }
  return bytes;
}
