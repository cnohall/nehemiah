# itch.io demo page

Everything for the Windows demo page on itch.io. Art comes from
`node store/steam/render.mjs` (cover.png 630x500, banner.png 960x300);
screenshots are copies of store/steam/screenshots.

## Build

```
Godot --headless --path . --export-release "Windows Demo" build/demo-windows/Nehemiah-Demo.exe
```

Preset "Windows Demo" (gitignored export_presets.cfg) sets the `demo` feature: days 1-9,
two stretches, end card with a "Get launch news" button (GameState.DEMO_NEWS_URL) until
DEMO_WISHLIST_URL holds a Steam page. Folder ships exe + pck + libgodotsteam dll +
steam_api64.dll. Without Steam running the game falls back to LAN / direct IP.

## Browser build (HTML5)

From the web worktree (C:\Programming\nehemiah-web, branch web-port):

```
Godot --headless --path . --export-release "Itch Web Demo" build/itch-web/index.html
butler push build/itch-web <itch-user>/nehemiah-the-wall:html5 --userversion 0.9.0
```

Preset "Itch Web Demo" (gitignored export_presets.cfg) = the tuned "Web" preset with the
`demo` feature, single-threaded (no SharedArrayBuffer needed) and no head_include (its
canonical/OG tags belong to play.nehemiahgame.com). On any host but nehemiahgame.com /
localhost (WebPage.home()), online play signals through wss://play.nehemiahgame.com/ws,
the invite-link button is hidden (friends type the room code) and play stats stay off.

On the html5 upload tick **This file will be played in the browser**, then under Embed
options: Viewport 1280 x 720, **Fullscreen button** on, **Click to launch in fullscreen**
off, **Automatically start on page load** off (100 MB download), **Mobile friendly** off,
**SharedArrayBuffer support** off.

## Upload (butler)

```
butler login                       # once, opens the browser
butler push build/demo-windows <itch-user>/nehemiah-the-wall:windows-demo --userversion 0.9.0
butler status <itch-user>/nehemiah-the-wall
```

Create the project on itch.io first (Dashboard > Create new project) so the slug exists.
After the first push, edit the upload on the page: tick **Windows** and **This file is a
demo**. Later pushes to the same channel update it in place (players on the itch app get
patches). Manual fallback: upload build/Nehemiah-Demo-web.zip (index.html at the zip
root) and build/Nehemiah-Demo-windows.zip.

## Page fields

| Field | Value |
|---|---|
| Title | Nehemiah: The Wall (Demo) |
| Project URL | nehemiah-the-wall |
| Short description | Co-op wall building and defense in 455 BCE Jerusalem. Free demo: the first 9 days. |
| Classification | Games |
| Kind of project | HTML (plays in the browser; the Windows zip sits below as a download) |
| Release status | In development |
| Pricing | No payments (or "$0 or donate") |
| Uploads | html5 channel (played in browser) + windows-demo channel (Windows, "This file is a demo") |
| Genre | Strategy |
| Tags | co-op, tower-defense, building, isometric, historical, bible, strategy, 3d, multiplayer, singleplayer |
| AI generation disclosure | your call (itch asks; see note below) |
| App store links | Steam, once the page exists |
| Custom noun | game |
| Languages | English, Spanish, Portuguese (Brazil), German, Korean |
| Inputs | Keyboard, Mouse, Xbox controller, Gamepad (any) |
| Accessibility | (leave unticked unless verified) |
| Multiplayer | Server-based networked multiplayer (browser room codes) + Ad-hoc networked multiplayer (download); Player count 1-4 |
| Average session | About a half-hour |
| Community | Comments |
| Visibility | Draft, then Public after a test download |

Theme: background #f6ecd6 (parchment), text #2b1d12, links/buttons #b5562a (terracotta),
banner.png as the header image, Cinzel (or Cormorant) for headings if offered.

## Description

Paste into the description field (rich text editor; ★ lines as bold headings).

---

**Rebuild the wall of Jerusalem with your friends before the enemy breaks through.**

It is 455 BCE. Jerusalem's wall lies in ruins, and Nehemiah has come home to raise it
again. You and up to three friends are the crew: carry wood, stone and mortar, work the
wall up course by course, and sling stones at the raiders who come to stop you. Builders
have their hands full, so someone always has to stand guard, just as in Nehemiah 4:17.

**This free demo covers the first 9 days:** the Sheep Gate, the Fish Gate and the morning
the enemy sends its first brute. The full game runs all 52 days around 12 gates.

★ **CO-OP FOR 1-4, RIGHT HERE IN THE BROWSER**
Host a game and share the five-letter room code; friends open this page, press Join Game
and type it in. Playing alone? Computer crew members fill the empty places and take your
orders.

★ **CARRY, BUILD, DEFEND**
Every stretch of wall goes up in three steps: timber, stone, mortar. Deliver the loads,
then stand at the wall and work it up. More hands build faster, and a hit stops the work.

★ **WAVES AND NIGHTFALL**
Enemies come in waves: a bell warns you, a pointer shows where they'll hit. Every day
ends when the stars come out, and each section must stand before nightfall on its last day.

★ **WATCH POSTS**
Raise watch posts behind the wall and keep their slingers stocked with stone. Every stone
in a post is a stone not in the wall. Choose well.

★ **GROUNDED IN THE ACCOUNT**
Short story cards follow the book of Nehemiah, with verses from the World English Bible.

★ **PLAY YOUR WAY**
Keyboard and mouse or a controller. English, Spanish, Portuguese, German and Korean.

**Play:** press Run game above, then the fullscreen button. A desktop browser (Chrome,
Edge or Firefox) works best; the first load is about 100 MB.

**Prefer a download?** The Windows version below looks sharper and runs smoother: unzip
(or use the itch app) and run Nehemiah-Demo.exe. Windows 10/11, 64-bit, a GPU with
Vulkan support. It plays online over Steam (with Steam running) or by IP on your network;
it can't join browser rooms.

Made by Takiko Games. News and launch updates: https://www.nehemiahgame.com

---

## Notes

- With Steam running, the demo still inits as app 480, so friends see "Playing Spacewar".
  Fixed once the Steam demo App ID exists (NetworkManager.STEAM_APP_ID).
- itch.io asks whether the project uses generative AI; answer for the art, music, text
  and code as they actually are.
- A web (HTML5) itch build needs the web-port branch plus absolute signaling/telemetry
  URLs and Worker CORS (see the web-port notes); not done.
