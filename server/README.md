# Nehemiah online server

One small Node process that does two jobs:

- **Signaling** (`/ws`): hands out 5-letter room codes and relays the WebRTC
  handshake between each joiner and the host. Game traffic never passes through
  it — once connected, players talk peer-to-peer.
- **Static hosting** of the web export (`build/web`), gzipped, so one deploy is
  the whole browser game. Optional: the game can live elsewhere (see below).

## Run locally

```sh
cd server
npm install
npm test          # protocol smoke test
npm start         # http://localhost:8787 — game + signaling
```

Export the web build first (from the repo root):

```sh
godot --headless --export-release "Web" build/web/index.html
```

Open `http://localhost:8787` in two browser windows: Host in one, then use the
room code or the "Copy invite link" button (`?room=CODE`) in the other.

Desktop builds use the same rooms (cross-play): with Steam running they default
to Steam, so pass `-- --online` (and `-- --signal=ws://host:8787/ws` if the
server isn't on localhost).

## Deploy

Any host that runs Node and allows WebSockets works (Render, Fly.io, Railway,
a VPS). With Docker, from the repo root after a web export:

```sh
docker build -f server/Dockerfile -t nehemiah .
docker run -p 8787:8787 nehemiah
```

Put it behind HTTPS — browsers need `wss://` from an `https://` page. The game
connects to the server that served the page, so nothing else to configure.

### Game hosted elsewhere (e.g. itch.io)

Set the project setting `nehemiah/online/signaling_url` to
`wss://your-server/ws` before exporting. `?signal=wss://…/ws` on the page URL
overrides it for testing.

## Environment

| Variable      | Default          | Purpose |
|---------------|------------------|---------|
| `PORT`        | `8787`           | Listen port |
| `STATIC_DIR`  | `../build/web`   | Web export to serve (skipped if missing) |
| `ICE_SERVERS` | Google + Cloudflare STUN | JSON array of `RTCIceServer`s sent to clients |

STUN alone connects most players. Some networks (strict/symmetric NAT, some
mobile carriers) need a TURN relay — add one via `ICE_SERVERS`, e.g.
`[{"urls":"stun:stun.l.google.com:19302"},{"urls":"turn:turn.example.com:3478","username":"u","credential":"p"}]`.
When a join can't connect, players see "Couldn't connect to the host — one of
your networks may block direct connections."

## Protocol

JSON text frames. Bump `PROTOCOL` in `server.js` **and**
`scenes/network_manager/webrtc_online.gd` together when it or the netcode changes;
mismatched clients get a clear "out of date" message.

| From → to        | Message |
|------------------|---------|
| server → client  | `hello {protocol, ice}` on connect |
| client → server  | `host {protocol}` / `join {code, protocol}` |
| server → client  | `hosted {code, id:1}` / `joined {code, id}` / `error {error}` |
| server → host    | `peer_joined {id}` / `peer_left {id}` |
| server → joiners | `closed` (host left) |
| either way       | `signal {to, kind: offer\|answer\|candidate, …}` → relayed with `from` |

Rooms hold 4 players; a room closes when its host disconnects.
