// Nehemiah online server: room-code signaling for WebRTC co-op, and (optionally)
// static hosting of the web export so one deploy serves both.
//
// Game traffic never touches this server — it only introduces peers. The host
// opens a room and gets a 5-letter code; joiners send the code, and the server
// relays WebRTC offers/answers/ICE candidates between each joiner and the host.
// After that the players talk peer-to-peer (DTLS data channels).
//
//   PORT          listen port (default 8787)
//   STATIC_DIR    folder with the web export (default ../build/web; skipped if missing)
//   ICE_SERVERS   JSON array of RTCIceServer objects, replaces the default STUN list.
//                 Add a TURN server here for players behind strict NATs, e.g.
//                 [{"urls":"stun:stun.l.google.com:19302"},
//                  {"urls":"turn:turn.example.com:3478","username":"u","credential":"p"}]

import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import zlib from "node:zlib";
import { WebSocketServer } from "ws";

// Bump together with WebRtcOnline.PROTOCOL when the handshake or netcode changes
export const PROTOCOL = 1;
const MAX_PLAYERS = 4;
const CODE_LEN = 5;
const CODE_CHARS = "ABCDEFGHJKLMNPQRSTUVWXYZ"; // no I/O: reads cleanly off a screen
const MAX_ROOMS = 2000;
const PING_MS = 25_000;

const DEFAULT_ICE = [
  { urls: ["stun:stun.l.google.com:19302", "stun:stun1.l.google.com:19302"] },
  { urls: "stun:stun.cloudflare.com:3478" },
];

const here = path.dirname(fileURLToPath(import.meta.url));

const MIME = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript",
  ".wasm": "application/wasm",
  ".pck": "application/octet-stream",
  ".png": "image/png",
  ".svg": "image/svg+xml",
  ".ico": "image/x-icon",
  ".json": "application/json",
  ".webmanifest": "application/manifest+json",
};

export function createServer({
  port = 8787,
  staticDir = path.resolve(here, "../build/web"),
  iceServers = DEFAULT_ICE,
  log = console.log,
} = {}) {
  const rooms = new Map(); // code -> { host: ws, peers: Map<id, ws> }

  const httpServer = http.createServer((req, res) => {
    const url = new URL(req.url, "http://x");
    if (url.pathname === "/health") {
      res.writeHead(200, { "content-type": "application/json" });
      res.end(JSON.stringify({ ok: true, rooms: rooms.size }));
      return;
    }
    serveStatic(staticDir, url.pathname, req, res);
  });

  const wss = new WebSocketServer({ server: httpServer, path: "/ws", maxPayload: 64 * 1024 });

  wss.on("connection", (ws) => {
    ws.alive = true;
    ws.on("pong", () => (ws.alive = true));
    send(ws, { type: "hello", protocol: PROTOCOL, ice: iceServers });
    ws.on("message", (raw) => {
      let msg;
      try {
        msg = JSON.parse(raw.toString());
      } catch {
        return;
      }
      if (msg && typeof msg === "object") handle(ws, msg);
    });
    ws.on("close", () => leave(ws));
  });

  function handle(ws, msg) {
    switch (msg.type) {
      case "host": {
        if (!checkProtocol(ws, msg) || ws.room) return;
        if (rooms.size >= MAX_ROOMS) return fail(ws, "The server is full, try again later.");
        const code = newCode();
        rooms.set(code, { host: ws, peers: new Map() });
        ws.room = code;
        ws.peerId = 1;
        send(ws, { type: "hosted", code, id: 1 });
        log(`room ${code} opened (${rooms.size} open)`);
        return;
      }
      case "join": {
        if (!checkProtocol(ws, msg) || ws.room) return;
        const code = String(msg.code || "").toUpperCase();
        const room = rooms.get(code);
        if (!room) return fail(ws, `No room with code ${code}.`);
        if (room.peers.size + 1 >= MAX_PLAYERS) return fail(ws, "That room is full.");
        const id = newPeerId(room);
        room.peers.set(id, ws);
        ws.room = code;
        ws.peerId = id;
        send(ws, { type: "joined", code, id });
        send(room.host, { type: "peer_joined", id });
        log(`room ${code}: peer ${id} joined (${room.peers.size + 1}/${MAX_PLAYERS})`);
        return;
      }
      case "signal": {
        // offer / answer / candidate — relayed between one joiner and the host only
        const room = rooms.get(ws.room);
        if (!room) return;
        const to = Number(msg.to);
        const target = to === 1 ? room.host : ws.peerId === 1 ? room.peers.get(to) : null;
        if (!target || target === ws) return;
        send(target, { ...msg, from: ws.peerId, to: undefined });
        return;
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

  function leave(ws) {
    const room = rooms.get(ws.room);
    if (!room) return;
    if (ws.peerId === 1) {
      for (const p of room.peers.values()) {
        send(p, { type: "closed" });
        p.room = null;
      }
      rooms.delete(ws.room);
      log(`room ${ws.room} closed (${rooms.size} open)`);
    } else if (room.peers.delete(ws.peerId)) {
      send(room.host, { type: "peer_left", id: ws.peerId });
    }
    ws.room = null;
  }

  function newCode() {
    for (;;) {
      let code = "";
      for (let i = 0; i < CODE_LEN; i++) code += CODE_CHARS[Math.floor(Math.random() * CODE_CHARS.length)];
      if (!rooms.has(code)) return code;
    }
  }

  function newPeerId(room) {
    for (;;) {
      const id = 2 + Math.floor(Math.random() * 0x7ffffffd); // 2 .. 2^31-1, as Godot expects
      if (!room.peers.has(id)) return id;
    }
  }

  // Free hosts drop idle sockets; pings keep lobbies alive and reap dead peers
  const pinger = setInterval(() => {
    for (const ws of wss.clients) {
      if (!ws.alive) {
        ws.terminate();
        continue;
      }
      ws.alive = false;
      ws.ping();
    }
  }, PING_MS);
  wss.on("close", () => clearInterval(pinger));

  return new Promise((resolve) => {
    httpServer.listen(port, () => {
      const hasStatic = fs.existsSync(path.join(staticDir, "index.html"));
      log(`nehemiah server on :${httpServer.address().port} — signaling at /ws` +
        (hasStatic ? `, serving ${staticDir}` : " (no web build to serve)"));
      resolve({
        port: httpServer.address().port,
        rooms,
        close: () => new Promise((r) => {
          for (const ws of wss.clients) ws.terminate();
          wss.close();
          httpServer.close(r);
        }),
      });
    });
  });
}

function send(ws, msg) {
  if (ws.readyState === 1) ws.send(JSON.stringify(msg));
}

function fail(ws, error) {
  send(ws, { type: "error", error });
}

// The wasm is ~40 MB raw, ~9 MB gzipped — compress once per build, keep in memory
const COMPRESSIBLE = new Set([".html", ".js", ".wasm", ".pck", ".json", ".svg"]);
const gzCache = new Map(); // file -> { mtimeMs, body }

function gzipped(file, st, cb) {
  const hit = gzCache.get(file);
  if (hit && hit.mtimeMs === st.mtimeMs) return cb(null, hit.body);
  fs.readFile(file, (err, raw) => {
    if (err) return cb(err);
    zlib.gzip(raw, { level: 6 }, (err2, body) => {
      if (err2) return cb(err2);
      gzCache.set(file, { mtimeMs: st.mtimeMs, body });
      cb(null, body);
    });
  });
}

function serveStatic(root, pathname, req, res) {
  let rel;
  try {
    rel = decodeURIComponent(pathname);
  } catch {
    rel = "/";
  }
  if (rel.endsWith("/")) rel += "index.html";
  const file = path.resolve(root, "." + path.posix.normalize(rel));
  if (!file.startsWith(path.resolve(root) + path.sep)) {
    res.writeHead(403).end();
    return;
  }
  fs.stat(file, (err, st) => {
    if (err || !st.isFile()) {
      res.writeHead(404, { "content-type": "text/plain" }).end("Not found");
      return;
    }
    const ext = path.extname(file).toLowerCase();
    const headers = {
      "content-type": MIME[ext] || "application/octet-stream",
      // The export's file names don't change between builds — always revalidate
      "cache-control": "no-cache",
      "last-modified": st.mtime.toUTCString(),
    };
    if (req.headers["if-modified-since"] === headers["last-modified"]) {
      res.writeHead(304, headers).end();
      return;
    }
    if (COMPRESSIBLE.has(ext) && /\bgzip\b/.test(req.headers["accept-encoding"] || "")) {
      gzipped(file, st, (err2, body) => {
        if (err2) return res.writeHead(500).end();
        res.writeHead(200, { ...headers, "content-encoding": "gzip", "content-length": body.length, vary: "accept-encoding" });
        res.end(body);
      });
      return;
    }
    res.writeHead(200, { ...headers, "content-length": st.size });
    fs.createReadStream(file).pipe(res);
  });
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  let iceServers = DEFAULT_ICE;
  if (process.env.ICE_SERVERS) iceServers = JSON.parse(process.env.ICE_SERVERS);
  createServer({
    port: Number(process.env.PORT) || 8787,
    staticDir: process.env.STATIC_DIR ? path.resolve(process.env.STATIC_DIR) : undefined,
    iceServers,
  });
}
