# TTS cache-key contract (Worker ↔ Flutter)

Single source of truth for how a sentence maps to an R2 object.
`workers/tts/src/cacheKey.ts` implements it; Flutter mirrors it in
`lib/core/audio/tts_backend_config.dart` (`ttsGearForRate`,
`ttsSpeedForGear`) plus the `ttsCacheKeyForTest` helper used by tests.

## Normalization (both sides identical)

1. Replace `___` → space, then `__` → space.
2. Replace `……` → space, then `…` → space.
3. Collapse runs of `_` → single space.
4. Collapse runs of whitespace → single space.
5. Trim. Empty result → 400 `empty text`.

## Gears

Only three speeds exist on the wire: `slow` / `normal` / `fast`,
mapped to MiniMax `speed` `0.5` / `0.7` / `1.0`.
The app slider (`0.2–0.8`, `0.42` = 正常) quantizes to the nearest gear,
so continuous slider movement cannot explode the key space.

## Key format

```
tts/v1/{MODEL_VERSION}/{voiceSlug}/{gear}/{sha256hex(normalizedText)}.mp3
```

- `MODEL_VERSION` e.g. `mm-speech28hd-v1` (wrangler var; bump to invalidate).
- `voiceId` allowlisted (`ALLOWED_VOICES`); unknown ids fall back to
  `DEFAULT_VOICE_ID` instead of erroring, so clients never get 400 for
  a typo'd voice.
- `voiceSlug` is a URL-safe alias, never the raw voice id (voice ids
  contain fullwidth parens / spaces that broke playback URLs):
  `gentle` / `mary` / `peter` / `waiter` for the four known voices,
  `v-<12hex of sha256(voiceId)>` for anything else. The full id is
  still sent to MiniMax on a cache MISS; only the key uses the slug.
- `sha256hex` over UTF-8 of the normalized text (WebCrypto server-side,
  `crypto` package client-side in tests).

## Examples

- text `早晨！`, voice `Cantonese_GentleLady`, gear `normal`
  → `tts/v1/mm-speech28hd-v1/gentle/normal/<sha256>.mp3`
- text `你好`, voice `Cantonese_ProfessionalHost（F)`, gear `normal`
  → `tts/v1/mm-speech28hd-v1/mary/normal/<sha256>.mp3`
- batch requests reuse the same per-item keys.
