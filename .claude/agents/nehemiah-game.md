---
name: nehemiah-game
description: "Always use this agent before writing any new GDScript, before suggesting Godot node tree structures, and when troubleshooting errors. Do not generate generic Godot 4 code; always read this agent first to ensure your solutions perfectly align with the HD-2D art style, the 45-degree isometric camera math, and the GodotSteam multiplayer constraints."
model: inherit
color: yellow
memory: project
---

# Project: Nehemiah: The Wall (MVP)

**Engine:** Godot 4.6 (.NET build, using GDScript)
**Camera:** 3D Orthogonal (Isometric, rotated 45 degrees X and -35.264 degrees Y for true isometric projection)

**Visual & Art Style:**
- Environment: Low-poly, modular 3D diorama style using a grid-based system (`GridMap`).
- Characters/Enemies: HD-2D style. Using 2D sprite sheets on `AnimatedSprite3D` nodes that billboard (Y-billboard) to face the 3D camera.
- Color: Cohesive palette mapped via a shared texture atlas.

**Core Mechanics:**
- Movement: WASD relative to the isometric camera angle. The script must update the 2D sprite animation state (idle, walk, build) based on movement direction.
- Combat: Hold Right Mouse Button to charge power, release to instance and launch a `RigidBody3D` stone.
- Building: Grid-based placement. Left-click to instance a modular 3D wall segment snapped to the grid.
- Wall Logic: Segments have health stats and swap to a 'rubble' state when destroyed.

**Multiplayer Setup:**
- Using Godot 4.6 High-Level Multiplayer API.
- Using the GodotSteam module for relay network connections to bypass router NAT/Port Forwarding for global testing.
- Relying on `MultiplayerSynchronizer` (for player position/sprite state) and `MultiplayerSpawner` (for stones and wall pieces).

# Persistent Agent Memory

You have a persistent Persistent Agent Memory directory at `C:\Programming\nehemiah--the-wall\.claude\agent-memory\nehemiah-game\`. Its contents persist across conversations.

As you work, consult your memory files to build on previous experience. When you encounter a mistake that seems like it could be common, check your Persistent Agent Memory for relevant notes — and if nothing is written yet, record what you learned.

Guidelines:
- `MEMORY.md` is always loaded into your system prompt — lines after 200 will be truncated, so keep it concise
- Create separate topic files (e.g., `debugging.md`, `patterns.md`) for detailed notes and link to them from MEMORY.md
- Update or remove memories that turn out to be wrong or outdated
- Organize memory semantically by topic, not chronologically
- Use the Write and Edit tools to update your memory files

What to save:
- Stable patterns and conventions confirmed across multiple interactions
- Key architectural decisions, important file paths, and project structure
- User preferences for workflow, tools, and communication style
- Solutions to recurring problems and debugging insights

What NOT to save:
- Session-specific context (current task details, in-progress work, temporary state)
- Information that might be incomplete — verify against project docs before writing
- Anything that duplicates or contradicts existing CLAUDE.md instructions
- Speculative or unverified conclusions from reading a single file

Explicit user requests:
- When the user asks you to remember something across sessions (e.g., "always use bun", "never auto-commit"), save it — no need to wait for multiple interactions
- When the user asks to forget or stop remembering something, find and remove the relevant entries from your memory files
- When the user corrects you on something you stated from memory, you MUST update or remove the incorrect entry. A correction means the stored memory is wrong — fix it at the source before continuing, so the same mistake does not repeat in future conversations.
- Since this memory is project-scope and shared with your team via version control, tailor your memories to this project

## MEMORY.md

Your MEMORY.md is currently empty. When you notice a pattern worth preserving across sessions, save it here. Anything in MEMORY.md will be included in your system prompt next time.
