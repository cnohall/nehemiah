# Nehemiah: The Wall — Game Design Document
**Version 0.3 | March 2026**

---

## 1. Overview

Cooperative 2–4 player HD-2D isometric action-strategy set in 445 BC Jerusalem. Players embody the workers and guards of Nehemiah's rebuilding effort, racing to reconstruct the city wall in 52 days while repelling Sanballat's increasingly desperate forces. Tone: urgent and collaborative — think Overcooked meets tower defense, grounded in biblical history.

**Core loop per day:**
1. Day begins — enemies spawn in waves
2. Players fight, carry stones, and place wall blocks simultaneously
3. Day ends when all enemies are killed
4. Night phase — day summary → cutscene (if scheduled) → upgrade window → autosave → dawn

**Win condition:** 52 days is the hard deadline (Nehemiah 6:15). Complete 250 blocks before then to win. Failing to finish in time = loss. This creates the most historical tension — finishing early is a bonus, not an accident.

---

## 2. Player Roles (max 4)

Roles chosen before game starts (lobby screen). Locked for the full run.

| Role | Stone Cap | Place Speed | Combat Bonus | Unique Trait |
|------|-----------|-------------|--------------|--------------|
| Builder | 5 | 1.4x faster (1.4s vs 2s) | Normal | Sees blueprint health overlays |
| Slinger | 5 | Normal | +30% throw range, +20% damage | Faster reload (0.35s vs 0.5s) |
| Porter | 10 | Normal | Normal | Instant quarry fill; can drop stones for others |

- **Builder** reduces `PLACE_DURATION` from 2.0s → 1.4s
- **Slinger** increases throw range and damage multiplier, reduces `RELOAD_TIME` to 0.35s
- **Porter** raises `MAX_STONES` to 10 and adds a drop-stones interaction (E near another player)

Role replicated via `MultiplayerSynchronizer`. Server validates role-dependent actions.

---

## 3. Enemy Types

All extend `BaseEnemy`. Wave manager selects types by day.

### 3.1 Basic Melee Warrior (current)
- Health 25, speed 3.0, damage 10 | All days

### 3.2 Wall Scaler
- Health 30, speed 2.5, damage 12 | Day 8+
- Navigates to wall perimeter → 2s climb animation → stands on top → attacks
- Must be knocked off by a stone before reaching the top

### 3.3 Ranged Attacker (Archer)
- Health 20, speed 2.0, damage 15/shot | Day 12+
- Stops at ~15 units standoff, fires slow projectile every 2.5s at players or wall blocks
- High priority target for Slingers

### 3.4 Battering Ram
- Health 200, speed 1.0, damage 40/hit | Day 18+, 1 per wave
- Ignores players, moves straight toward nearest wall section or gate
- Requires focused stone fire to destroy before it reaches the wall

### 3.5 Boss: Sanballat's Champion
- Health 400, speed 2.5, damage 25 | Days 10, 26, 52
- Charge attack (1s wind-up), immune to first stone per encounter (armor)
- On death: drops 3 stones

---

## 4. Upgrade System

Shown during night hold phase. Each player independently picks one upgrade from their role-specific pool. 30s timer or "Ready" button.

### Global Upgrades (any role, once each)
- **Reinforced Blocks**: block health 50 → 75
- **Torches**: enemies pathfind 20% slower at night (permanent)
- **Extra Quarry**: second quarry spawns at Vector3(20, 0.5, 20)

### Role Upgrades
**Builder:** Masonry I (place costs 0 stones) | Double Layer (1 action = 2 blocks, day 20+)
**Slinger:** Precision Aim (damage mult 1.2 → 1.8) | Rapid Fire (reload 0.35 → 0.2s)
**Porter:** Beast of Burden (MAX_STONES → 15) | Swift Feet (no stamina drain when carrying 0 stones)

---

## 5. Structures

### 5.1 Watchtower
- Cost: 8 stones | Build time: 6s | Health: 150
- Only on 4 designated `WatchtowerSpot` nodes at historically relevant gate positions
- Auto-fires stone projectile at nearest enemy within 20 units every 3s (server-side)
- Can be destroyed by enemies / Battering Ram

### 5.2 Gates (Phase 4+)
- Openable/closeable via E at gate positions
- Open: enemies pathfind through; Closed: acts as wall section

---

## 6. Day/Night Flow (Extended)

```
[Day Start] → wave_started signal
    ↓
[Daytime] — enemies spawn, players fight + build
    ↓
[Wave Cleared] → wave_cleared signal
    ↓
[Night Fall] — 2.5s light transition (existing)
    ↓
[Day Summary Screen] — kills, blocks placed, damage taken, wall %
    ↓
[Cutscene] — if scheduled for this day
    ↓
[Upgrade Window] — 30s or all players ready
    ↓
[Autosave]
    ↓
[Dawn] — 2.5s light transition → next day
```

---

## 7. Cutscenes

In-engine text-overlay style: parchment background panel, speaker name, dialogue text, "Continue" button. All clients see simultaneously (server-driven RPC). No video files needed.

| Day | Event |
|-----|-------|
| Before Day 1 | Nehemiah's prayer and commission from Artaxerxes |
| After Day 5 | Sanballat mocks Nehemiah |
| After Day 10 | Enemy council plots attack (Sanballat, Tobiah, Geshem) |
| Before Day 13 | Artaxerxes sends a supply caravan |
| After Day 20 | Tobiah's letter campaign, workers grow afraid |
| After Day 35 | Nehemiah arms the workers (trowel + sword) |
| After Day 51 | One night left — wall almost complete |
| Win | Nehemiah 6:15 quote |
| Loss | Jerusalem falls again |

---

## 8. Day Summary Screen

Shown before upgrade window. Stats tracked per day (server collects, broadcasts via RPC):
- Enemies killed (total + per player)
- Blocks placed (total + per player)
- Stones carried (per player)
- Player deaths this day
- Days remaining
- Wall completion % (blocks_placed / 250)

---

## 9. Save System

Server saves at start of each night phase. JSON file at `user://save.json`.

```json
{
  "day": 12,
  "blocks": [{"pos": {...}, "rot": 1.23}],
  "block_health": {"Block_x_y_z": 38.5},
  "upgrades": {"1": ["reinforced_blocks"], "2": ["precision_aim"]},
  "player_roles": {"1": "builder", "2": "slinger"}
}
```

"Continue" button in lobby if save exists. Late-joining clients receive state via extended `_receive_roster` RPC.

---

## 10. Audio

**Music:** main menu (ambient), daytime tension loop (escalates mid-wave), night (softer), boss variant
**SFX:** stone throw charge, stone impact (3 surface variants), block placement, enemy hit, player hit/death, day complete fanfare, night ambience

`AudioManager` autoload with `play_sfx(name)` and `play_music(name)`. Two AudioStreamPlayers for crossfaded music.

---

## 11. Win / Loss Conditions

| Condition | Result |
|-----------|--------|
| 250 blocks placed before day 52 ends | WIN |
| Temple breached by an enemy | LOSS |
| Day 52 ends, wall incomplete | LOSS |
| All players dead simultaneously | LOSS |

---

## 12. Historical Notes

- Wall circuit: Nehemiah 3, clockwise from Sheep Gate
- 52 days: Nehemiah 6:15 (Elul 25, 445 BC)
- Enemy leaders: Sanballat the Horonite, Tobiah the Ammonite, Geshem the Arab
- Persian king: Artaxerxes I (465–424 BC)
- Workers armed while building: Nehemiah 4:17 ("trowel in one hand, weapon in the other")
- Slinger role directly references the Nehemiah 4:13 garrison

---

## Phased Implementation Roadmap

### Phase 0 — Stabilization (Do first)
Extract `BuildingManager.gd` from `main.gd`. Move: `request_place_block`, `do_place_block`, `on_block_destroyed`, `_remove_block_rpc`, `_restore_blueprint`, `get_stack_at`, `get_nearest_placeable`, `get_placeable_angle`, `_place_starting_ruins`, `blocks_placed`, `BLOCKS_FOR_WIN`.

Result: `main.gd` ~300 lines, `BuildingManager.gd` ~200 lines. Game plays identically.

**New file:** `scenes/building_manager/building_manager.gd`

---

### Phase 1 — Player Roles
- Role select screen in lobby
- Per-role stat constants applied in `player.gd`
- `role` var replicated via MultiplayerSynchronizer
- HUD shows role name

**New files:** `scenes/ui/role_select_screen.tscn`
**Modified:** `player.gd`, `network_manager.gd`, `main.gd`

---

### Phase 2 — Enemy Types
- `base_enemy.gd` extracted from `enemy.gd`
- Wall Scaler, Ranged Attacker, Battering Ram, Boss Champion added
- `wave_manager.gd` selects enemy type by day with weighted random

**New files:** `scenes/enemy/base_enemy.gd`, `wall_scaler.gd`, `ranged_enemy.gd`, `battering_ram.gd`, `boss_champion.gd`, `enemy_projectile.gd`

---

### Phase 3 — Night Phase: Summary + Upgrades + Save
- Extended `NIGHT_HOLD` phase
- Day summary screen (per-player stats)
- Upgrade panel (role-specific choices)
- Autosave to JSON

**New files:** `scenes/ui/day_summary_screen.tscn`, `scenes/ui/upgrade_panel.tscn`, `scenes/upgrade_manager/upgrade_manager.gd`, `scenes/save_manager/save_manager.gd`

---

### Phase 4 — Cutscenes + Watchtowers + Audio
- Text-overlay cutscene system
- Watchtower structure at designated spots
- `AudioManager` autoload with music + SFX

**New files:** `scenes/cutscene_manager/cutscene_manager.gd`, `scenes/cutscene_manager/cutscene_data.gd`, `scenes/ui/cutscene_panel.tscn`, `scenes/structures/watchtower.gd`, `scenes/audio_manager/audio_manager.gd`

---

### Phase 5 — Polish + Balance
- Gates mechanic
- Minimap: show watchtowers, enemy types
- Enemy difficulty tuning per day
- Win/loss cutscene screens
- `get_stack_at()` O(n) optimization → cached `_stack_counts: Dictionary`
- Controller support

---

## Design Decisions (locked)

| # | Question | Decision |
|---|----------|----------|
| 1 | Wall finished before day 52? | Game ends immediately on wall completion |
| 2 | Roles locked or switchable? | Locked for full run |
| 3 | Porter stone transfer? | Drop on ground (anyone can pick up) |
| 4 | Wall Scalers — what do they do at the top? | Jump into city, head for the temple |
| 5 | Battering Ram destroyable before wall? | Yes — rewards Slinger coordination |
| 6 | Upgrades: shared pool or private? | Private screen per player |
| 7 | Upgrade phase: timer or ready button? | 30s timer, ends early if all press Ready |
| 8 | Save slots? | One slot, overwritten each night |
| 9 | Save shareable across machines? | Host machine only — tackle much later |
| 10 | Cutscene dismiss: one or all? | Best practice: all clients confirm |
| 11 | Target platform? | Windows primary; other platforms if trivial |
