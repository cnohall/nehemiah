# Multiplayer Connection Guide

The game uses **ENet** (built into Godot — no extra installs needed).
Two players need a way to reach each other's IP. Choose an option below.

---

## Option 1 — Same LAN (simplest)

Both players on the same Wi-Fi or wired network.

1. **Host** clicks **Host Game**. Open a command prompt and run `ipconfig`.
   Share the **IPv4 Address** (looks like `192.168.x.x`) with your friend.
2. **Client** types that IP into the **Host IP** field, leaves port as `7777`, clicks **Join Game**.
3. Windows Firewall will prompt the host the first time — click **Allow**.

---

## Option 2 — Tailscale (easiest for internet play)

Tailscale creates a private virtual network between your machines. No port forwarding needed.

1. Both players install **Tailscale**: https://tailscale.com/download
2. Both sign in (free account, Google/GitHub login works).
3. Both join the **same Tailscale network** (the host shares their network name or sends an invite from the Tailscale admin panel).
4. **Host** clicks **Host Game**. Open the Tailscale tray icon — copy the **Tailscale IP** (looks like `100.x.x.x`).
5. **Client** types that `100.x.x.x` IP into **Host IP**, clicks **Join Game**.

No firewall rules or port forwarding needed. Tailscale handles everything.

---

## Option 3 — ZeroTier (alternative to Tailscale)

1. Both players install **ZeroTier One**: https://www.zerotier.com/download/
2. Host creates a free network at https://my.zerotier.com → **Create A Network** → copy the **Network ID**.
3. Both players open ZeroTier → **Join Network** → paste the Network ID → click **Join**.
4. Host approves both members in the ZeroTier web panel (Members section → tick the checkboxes).
5. **Host** finds their ZeroTier IP in the ZeroTier tray icon (looks like `10.x.x.x` or `192.168.196.x`).
6. **Client** types that IP into **Host IP**, clicks **Join Game**.

---

## Option 4 — Port Forwarding (no third-party software)

Only the host needs to do this. Requires router access.

1. **Host** opens their router admin page (usually `192.168.1.1` or `192.168.0.1` in a browser).
2. Find **Port Forwarding** (sometimes under "Advanced" or "NAT").
3. Forward **UDP port 7777** to the host machine's local IP (get it from `ipconfig`).
4. **Host** finds their **public IP** at https://whatismyip.com
5. **Client** types that public IP into **Host IP**, clicks **Join Game**.

---

## Default Port

The game uses port **7777** (UDP). This can be changed in `network_manager.gd` → `DEFAULT_PORT`.
