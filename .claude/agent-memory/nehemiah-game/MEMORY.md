# Nehemiah: The Wall — Agent Memory

## Project Structure
- Engine: Godot 4.6 .NET build, GDScript only (no C#)
- Physics: Jolt Physics (set in project.godot)
- Renderer: Forward Plus, D3D12
- Scenes live in `scenes/` subdirectories
- Key files: `scenes/player/player.gd`, `scenes/network_manager/network_manager.gd`

## Key Architectural Patterns

### Isometric Camera Math
- Camera angles: X=45°, Y=-35.264° (true isometric)
- WASD movement: project camera's local `-Z` (forward) and `+X` (right) onto the
  XZ plane (zero out .y, then normalize) before combining with raw input.
- Never use world-axis-aligned directions for movement; always derive from camera basis.

### Animation Direction Resolution (HD-2D Billboard)
- AnimatedSprite3D uses `Y_BILLBOARD` mode — always faces the camera.
- Resolve animation direction in **screen space**, not world space.
- Steps: world_dir → dot with camera basis.x (screen_x) + dot with flattened
  camera basis.y (screen_y) → atan2(screen_x, screen_y) → snap to 45° octant.
- Use `fmod(snapped_angle + 360, 360)` to get a clean [0,360) range for `match`.
- 16 required animations: `idle_*` and `walk_*` for each of 8 directions.
- `_last_facing` variable preserves facing direction when transitioning to idle.

### MultiplayerSynchronizer Setup
- Configure via `SceneReplicationConfig` in `_ready()`, NOT in the editor.
- `_sync.root_path = NodePath("..")` points sync at the parent CharacterBody3D.
- Synced properties: `global_position` and `current_animation` (a plain `var`).
- Call `property_set_spawn(..., true)` AND `property_set_watch(..., true)` on each.
- Authority check: `is_multiplayer_authority()` gates all input/physics logic.
- `set_multiplayer_authority(peer_id)` is called externally by the MultiplayerSpawner.

### GodotSteam / NetworkManager Patterns
- Autoload is a plain `.gd` (no .tscn) — UI nodes built in code via `Node.new()`.
- `Steam.runCallbacks()` MUST be called every `_process` frame or Steam signals never fire.
- Init: `Steam.steamInitEx(true, APP_ID)` → returns `{"status": int, "verbal": String}`, status 0 = OK.
- `Steam.getSteamID()` and `Steam.getPersonaName()` only work AFTER successful init.
- Host flow: `Steam.createLobby()` → `lobby_created` signal → `SteamMultiplayerPeer.create_host(0)`.
- Client flow: `Steam.joinLobby(id)` → `lobby_joined` signal → read `host_steam_id` from lobby data
  → `SteamMultiplayerPeer.create_client(host_steam_id, 0)`.
- `create_host(virtual_port: int)` — 1 arg only. `create_client(steam_id: int, virtual_port: int)` — 2 args only. NO options array.
- Store host's Steam ID in lobby metadata: `Steam.setLobbyData(lobby_id, "host_steam_id", str(_steam_id))`.
- Steam SDR relay (NAT bypass) is negotiated automatically — no options array needed or accepted.
- Do NOT call `Steam.runCallbacks()` — this GodotSteam build processes callbacks automatically. That method does not exist.
- GodotSteam 4.14 breaking change: removed first argument for stat request in steamInit/steamInitEx. `steamInitEx(true, APP_ID)` is the correct 2-arg signature for 4.14+.
- GodotSteam 4.17 + Steamworks SDK 1.63 note: Windows projects are meant to work with Proton 11 on Linux/Deck. No API breakage for init.
- `initialize_on_startup=false` + manual `Steam.steamInitEx(true, APP_ID)` call is the CORRECT pattern for the GDExtension flavour. Do not switch to `initialize_on_startup=true`.
- `embed_callbacks=false` is correct for the GDExtension flavour — callbacks are embedded in the native library, not managed by a GDScript _process loop.
- "ConnectToGlobalUser failed" means the Steam client IPC pipe is broken. Root causes in order of likelihood: (1) Godot or Steam running as Administrator but not the other. (2) `steam_appid.txt` in wrong directory (must be in `C:/Godot/` alongside the .exe). (3) A stale `steam_[appid].tmp` lock file. (4) Steam not fully started. (5) A `~libgodotsteam.windows.template_debug.x86_64.dll` lock artifact in `addons/godotsteam/win64/` — created when the mono build held the DLL open during a reload; delete it and relaunch. (6) A stray `steam_api64.dll` in the project root — only one copy should exist, at `addons/godotsteam/win64/steam_api64.dll`, as declared in the .gdextension [dependencies] block; the project root copy adds DLL resolution ambiguity and must be deleted.
- After any "ConnectToGlobalUser failed" incident: check for `~lib*.dll` in `addons/godotsteam/win64/` and delete it; check for `steam_api64.dll` in the project root and delete it.
- Godot editor path confirmed: `C:/Godot/Godot_v4.6.1-stable_mono_win64.exe`. The `steam_appid.txt` must exist in `C:/Godot/` alongside this exe.
- No UAC/requireAdministrator flag found in the Godot exe manifest, and no AppCompatFlags\Layers registry entry for Godot — elevated-process mismatch is only a risk if the user manually right-clicks "Run as administrator".
- `lobby_created` result: 1 = STEAM_RESULT_OK. `lobby_joined` response: 1 = LOBBY_ENTER_SUCCESS.
- `multiplayer.connected_to_server` fires on CLIENT only — right moment to transition to gameplay.
- `multiplayer.peer_connected` fires on ALL peers (host + other clients) for each new joiner.
- Expose `hide_menu()` / `show_menu()` / `disconnect_from_lobby()` as public API for other scenes.
- Guard all UI node writes with `is_instance_valid()` to survive scene transitions.

### Input Map Actions Required
- `move_left`, `move_right`, `move_up`, `move_down` (set in Project → Input Map)

## See Also
- `scenes/player/player.gd` — movement, animation, MultiplayerSynchronizer patterns.
- `scenes/network_manager/network_manager.gd` — GodotSteam lobby + peer setup.
