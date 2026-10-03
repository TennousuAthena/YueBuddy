# YueBuddy TTS Worker

Cloudflare Worker + R2 cache in front of MiniMax sync TTS (`POST /v1/t2a_v2`).
Lazy-load design: first request for a sentence回源 MiniMax, every later
request (any user) hits R2 / CDN.

## Routes

- `POST /v1/tts` `{text, voiceId?, gear?}` → `{url, cache: HIT|MISS, gear}`
- `POST /v1/tts/batch` `{items: [{text, voiceId?}], gear?}` → `{urls[], cacheHits, gear}`
- `GET /a/<key>` → `audio/mpeg`, immutable, `X-Cache: HIT`
- `GET /health` → `{ok: true}`

CORS is open (`*`) so Flutter Web works without extra setup.

## Setup

```bash
cd workers/tts
npm install
# R2 bucket (once per account)
wrangler r2 bucket create yuebuddy-tts-audio
# MiniMax key (never commit this)
wrangler secret put MINIMAX_API_KEY
# Local run / deploy
npm run dev
npm run deploy
```

Optional hardening later: add a Cloudflare Rate Limiting rule in front of
`/v1/tts*` and fill in `src/auth.ts` (`Authorization` header is already
reserved by clients). No route changes needed.

## Config (wrangler.toml [vars])

`MINIMAX_BASE_URL`, `MINIMAX_MODEL`, `MODEL_VERSION`,
`DEFAULT_VOICE_ID`, `LANGUAGE_BOOST`, `ALLOWED_VOICES`,
`MAX_TEXT_LENGTH` (200), `MAX_BATCH_ITEMS` (20), `RATE_LIMIT_PER_MIN` (60).

Bump `MODEL_VERSION` when the upstream model or audio settings change;
old cache keys become unreachable and age out untouched.
