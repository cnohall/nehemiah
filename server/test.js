// Protocol smoke test: host, join, relay, full room, host leaving. `npm test`
import assert from "node:assert/strict";
import WebSocket from "ws";
import { createServer, PROTOCOL } from "./server.js";

const srv = await createServer({ port: 0, log: () => {} });
const url = `ws://localhost:${srv.port}/ws`;

function client() {
  const ws = new WebSocket(url);
  const inbox = [];
  const waiters = [];
  ws.on("message", (raw) => {
    const msg = JSON.parse(raw.toString());
    const i = waiters.findIndex((w) => w.type === msg.type);
    if (i >= 0) waiters.splice(i, 1)[0].resolve(msg);
    else inbox.push(msg);
  });
  return {
    ws,
    send: (m) => ws.send(JSON.stringify(m)),
    next: (type) => {
      const i = inbox.findIndex((m) => m.type === type);
      if (i >= 0) return Promise.resolve(inbox.splice(i, 1)[0]);
      return new Promise((resolve, reject) => {
        waiters.push({ type, resolve });
        setTimeout(() => reject(new Error(`timeout waiting for ${type}`)), 2000);
      });
    },
  };
}

const host = client();
assert.ok((await host.next("hello")).ice.length > 0);
host.send({ type: "host", protocol: PROTOCOL });
const { code } = await host.next("hosted");
assert.match(code, /^[A-Z]{5}$/);

const a = client();
await a.next("hello");
a.send({ type: "join", code: code.toLowerCase(), protocol: PROTOCOL });
const { id: aId } = await a.next("joined");
assert.ok(aId >= 2);
assert.equal((await host.next("peer_joined")).id, aId);

// Relay both ways, with sender stamped
host.send({ type: "signal", to: aId, kind: "offer", sdp: "x" });
const offer = await a.next("signal");
assert.deepEqual([offer.from, offer.kind, offer.sdp], [1, "offer", "x"]);
a.send({ type: "signal", to: 1, kind: "answer", sdp: "y" });
assert.equal((await host.next("signal")).from, aId);

// Wrong protocol / unknown code / full room
const old = client();
await old.next("hello");
old.send({ type: "join", code, protocol: PROTOCOL - 1 });
assert.match((await old.next("error")).error, /out of date/);
old.send({ type: "join", code: "ZZZZZ", protocol: PROTOCOL });
assert.match((await old.next("error")).error, /No room/);
const b = client(), c = client();
for (const p of [b, c]) {
  await p.next("hello");
  p.send({ type: "join", code, protocol: PROTOCOL });
  await p.next("joined");
}
old.send({ type: "join", code, protocol: PROTOCOL });
assert.match((await old.next("error")).error, /full/);

// Joiner leaves → host told; host leaves → joiners told, room gone
b.ws.close();
assert.ok((await host.next("peer_left")).id >= 2);
host.ws.close();
await a.next("closed");
await c.next("closed");
await new Promise((r) => setTimeout(r, 50));
assert.equal(srv.rooms.size, 0);

for (const p of [a, c, old]) p.ws.close();
await srv.close();
console.log("PASS");
