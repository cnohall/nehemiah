# Nehemiah on Cloudflare

The browser game and its online rooms on one domain, on Cloudflare's free plan:

- **Worker** (`src/index.js`) serves the web export from **R2** (the ~40 MB wasm is
  over the 25 MB static-asset limit, so it's stored pre-gzipped: ~10 MB on the wire).
- **Durable Object** `Lobby` does room-code signaling (`/ws`), same protocol as
  `server/server.js`. Hibernating WebSockets, so an idle lobby costs nothing.
- Optional **Cloudflare TURN** for players behind strict NATs.

`server/` stays the local dev server (desktop cross-play, headless tests).

## One-time setup

```sh
cd worker
npm install
npx wrangler login
npx wrangler r2 bucket create nehemiah-game
```

Add the domain in `wrangler.jsonc`:

```jsonc
"routes": [{ "pattern": "example.com", "custom_domain": true }]
```

TURN (optional): Cloudflare dashboard → Realtime → TURN Server → create a key, then

```sh
npx wrangler secret put TURN_KEY_ID
npx wrangler secret put TURN_KEY_API_TOKEN
```

## Deploy

```sh
npm run deploy        # Godot web export → R2 (gzipped) → wrangler deploy
node deploy.mjs --skip-export   # reuse build/web
```

Needs the "Web" preset in the repo root's `export_presets.cfg` (gitignored) and
`GODOT` pointing at the Godot 4.7.2 console binary if it isn't the default path.

## Local

```sh
npm run upload:local  # export + upload into the local R2
npm run dev           # http://localhost:8787
cd ../server && SERVER=http://localhost:8787 npm test   # protocol test against the Worker
```

Change the protocol in three places together: `src/index.js`, `server/server.js`,
`WebRtcOnline.PROTOCOL`.
