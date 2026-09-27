// Nehemiah on Cloudflare: the browser game (from R2) + room-code signaling for
// WebRTC co-op (a Durable Object), on one domain. Same protocol as server/server.js,
// which stays the local/desktop dev server — keep the two in step.
//
// Game traffic never touches this — it only introduces peers. The host opens a
// room and gets a 5-letter code; joiners send the code, and the Lobby relays
// WebRTC offers/answers/ICE candidates between each joiner and the host.
//
// Bindings (wrangler.jsonc): LOBBY (Durable Object), GAME (R2 bucket with the web export)
// Optional secrets for Cloudflare TURN (players behind strict NATs):
//   TURN_KEY_ID, TURN_KEY_API_TOKEN

import { DurableObject } from "cloudflare:workers";

// Bump together with WebRtcOnline.PROTOCOL and server/server.js
const PROTOCOL = 1;
const MAX_PLAYERS = 4;
const CODE_LEN = 5;
const CODE_CHARS = "ABCDEFGHJKLMNPQRSTUVWXYZ"; // no I/O: reads cleanly off a screen
const MAX_ROOMS = 2000;
const MAX_MESSAGE = 64 * 1024;
const TURN_TTL = 24 * 3600;       // credential lifetime, seconds
const TURN_REFRESH = 6 * 3600;    // hand out creds with at least this much life left

const DEFAULT_ICE = [
  { urls: ["stun:stun.cloudflare.com:3478", "stun:stun.l.google.com:19302"] },
];

export default {
  async fetch(req, env) {
    const url = new URL(req.url);
    if (url.pathname === "/ws" || url.pathname === "/health") {
      return env.LOBBY.get(env.LOBBY.idFromName("lobby")).fetch(req);
    }
    // AI assistants look for these on whatever host they land on; the site keeps them
    if (url.pathname === "/llms.txt" || url.pathname === "/llms-full.txt") {
      return Response.redirect(`https://www.nehemiahgame.com${url.pathname}`, 301);
    }
    return serveGame(req, env, url);
  },
};

// One lobby holds every room: a hobby game's worth of sockets fits one object
// easily, and the WebSocket hibernation API means an idle lobby costs nothing.
// Hibernation drops memory, so each socket carries its room/id as an attachment
// and the room table is rebuilt from those on wake.
export class Lobby extends DurableObject {
  constructor(ctx, env) {
    super(ctx, env);
    this.rooms = new Map(); // code -> { host: ws|null, peers: Map<id, ws> }
    this.turn = null;       // { ice, expires }
    for (const ws of ctx.getWebSockets()) {
      const { room, peerId } = ws.deserializeAttachment() || {};
      if (!room) continue;
      const r = this.#room(room);
      if (peerId === 1) r.host = ws;
      else r.peers.set(peerId, ws);
    }
  }

  async fetch(req) {
    if (new URL(req.url).pathname === "/health") {
      return Response.json({ ok: true, rooms: this.rooms.size });
    }
    if (req.headers.get("Upgrade") !== "websocket") {
      return new Response("Expected a WebSocket", { status: 426 });
    }
    const ice = await this.#ice();
    const [client, server] = Object.values(new WebSocketPair());
    this.ctx.acceptWebSocket(server);
    server.serializeAttachment({});
    send(server, { type: "hello", protocol: PROTOCOL, ice });
    return new Response(null, { status: 101, webSocket: client });
  }

  webSocketMessage(ws, raw) {
    if (typeof raw !== "string" || raw.length > MAX_MESSAGE) return;
    let msg;
    try {
      msg = JSON.parse(raw);
    } catch {
      return;
    }
    if (msg && typeof msg === "object") this.#handle(ws, msg);
  }

  webSocketClose(ws, code) {
    this.#leave(ws);
    try {
      ws.close(code === 1005 ? 1000 : code);
    } catch {}
  }

  webSocketError(ws) {
    this.#leave(ws);
  }

  #handle(ws, msg) {
    const me = ws.deserializeAttachment() || {};
    switch (msg.type) {
      case "host": {
        if (!checkProtocol(ws, msg) || me.room) return;
        if (this.rooms.size >= MAX_ROOMS) return fail(ws, "The server is full, try again later.");
        const code = this.#newCode();
        this.#room(code).host = ws;
        ws.serializeAttachment({ room: code, peerId: 1 });
        send(ws, { type: "hosted", code, id: 1 });
        return;
      }
      case "join": {
        if (!checkProtocol(ws, msg) || me.room) return;
        const code = String(msg.code || "").toUpperCase();
        const room = this.rooms.get(code);
        if (!room || !room.host) return fail(ws, `No room with code ${code}.`);
        if (room.peers.size + 1 >= MAX_PLAYERS) return fail(ws, "That room is full.");
        const id = newPeerId(room);
        room.peers.set(id, ws);
        ws.serializeAttachment({ room: code, peerId: id });
        send(ws, { type: "joined", code, id });
        send(room.host, { type: "peer_joined", id });
        return;
      }
      case "signal": {
        // offer / answer / candidate — relayed between one joiner and the host only
        const room = this.rooms.get(me.room);
        if (!room) return;
        const to = Number(msg.to);
        const target = to === 1 ? room.host : me.peerId === 1 ? room.peers.get(to) : null;
        if (!target || target === ws) return;
        send(target, { ...msg, from: me.peerId, to: undefined });
        return;
      }
    }
  }

  #leave(ws) {
    const { room: code, peerId } = ws.deserializeAttachment() || {};
    const room = this.rooms.get(code);
    ws.serializeAttachment({});
    if (!room) return;
    if (peerId === 1) {
      for (const p of room.peers.values()) {
        send(p, { type: "closed" });
        p.serializeAttachment({});
      }
      this.rooms.delete(code);
    } else if (room.peers.delete(peerId)) {
      send(room.host, { type: "peer_left", id: peerId });
    }
  }

  #room(code) {
    let r = this.rooms.get(code);
    if (!r) this.rooms.set(code, (r = { host: null, peers: new Map() }));
    return r;
  }

  #newCode() {
    for (;;) {
      let code = "";
      for (let i = 0; i < CODE_LEN; i++) code += CODE_CHARS[Math.floor(Math.random() * CODE_CHARS.length)];
      if (!this.rooms.has(code)) return code;
    }
  }

  // Short-lived Cloudflare TURN credentials, shared across players until they
  // get old. Without the secrets (or if the API is down) it's STUN only.
  async #ice() {
    const { TURN_KEY_ID: id, TURN_KEY_API_TOKEN: token } = this.env;
    if (!id || !token) return DEFAULT_ICE;
    const now = Date.now() / 1000;
    if (this.turn && this.turn.expires - now > TURN_REFRESH) return this.turn.ice;
    try {
      const res = await fetch(
        `https://rtc.live.cloudflare.com/v1/turn/keys/${id}/credentials/generate-ice-servers`,
        {
          method: "POST",
          headers: { authorization: `Bearer ${token}`, "content-type": "application/json" },
          body: JSON.stringify({ ttl: TURN_TTL }),
        },
      );
      if (!res.ok) throw new Error(`TURN ${res.status}`);
      const { iceServers } = await res.json();
      // Browsers time out on the port-53 variants — drop them
      const ice = [].concat(iceServers).map((s) => ({
        ...s,
        urls: [].concat(s.urls).filter((u) => !/:53(\?|$)/.test(u)),
      })).filter((s) => s.urls.length);
      this.turn = { ice, expires: now + TURN_TTL };
      return ice;
    } catch (e) {
      console.error("TURN credentials failed:", e);
      return this.turn ? this.turn.ice : DEFAULT_ICE;
    }
  }
}

function checkProtocol(ws, msg) {
  if (msg.protocol === PROTOCOL) return true;
  fail(ws, msg.protocol > PROTOCOL
    ? "The server is older than this game — try again after it updates."
    : "This game version is out of date — refresh the page or update.");
  return false;
}

function newPeerId(room) {
  for (;;) {
    const id = 2 + Math.floor(Math.random() * 0x7ffffffd); // 2 .. 2^31-1, as Godot expects
    if (!room.peers.has(id)) return id;
  }
}

function send(ws, msg) {
  try {
    ws.send(JSON.stringify(msg));
  } catch {}
}

function fail(ws, error) {
  send(ws, { type: "error", error });
}

// The web export lives in R2 (the wasm is ~40 MB, over the 25 MB static-asset
// limit). deploy.mjs uploads it pre-gzipped with content-encoding set, so it's
// passed through as-is.
async function serveGame(req, env, url) {
  if (req.method !== "GET" && req.method !== "HEAD") {
    return new Response("Method not allowed", { status: 405 });
  }
  let key;
  try {
    key = decodeURIComponent(url.pathname).replace(/^\/+/, "");
  } catch {
    key = "";
  }
  if (key === "" || key.endsWith("/")) key += "index.html";
  if (key.split("/").includes("..")) return new Response("Not found", { status: 404 });
  const obj = await env.GAME.get(key, { onlyIf: req.headers });
  if (!obj) return new Response("Not found", { status: 404 });
  const headers = new Headers();
  obj.writeHttpMetadata(headers);
  headers.set("etag", obj.httpEtag);
  // The export's file names don't change between builds — always revalidate
  headers.set("cache-control", "no-cache");
  if (!("body" in obj)) return new Response(null, { status: 304, headers });
  return new Response(req.method === "HEAD" ? null : obj.body, { headers, encodeBody: "manual" });
}
