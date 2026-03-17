# Implementation Plan: Priority Wall Building Improvements

This plan details the implementation of three high-priority enhancements for the wall building system: **Carried Item Visuals**, **Blueprint/Ghost Effect**, and **Dynamic Audio Cues**.

## 1. Carried Item Visuals
**Objective:** Make the player's carried items visible in their hands.

### Changes
- **`scenes/player/material_item.gd`**:
    - Refine `pick_up()` to position the item more naturally relative to the player's hands.
    - Ensure the item is parented to a specific "Hand" node or follow the player's movement better.
    - Add a small "hop" or "sway" animation to the carried item during movement to simulate weight.
- **`player.tscn`**:
    - Add a `RemoteTransform3D` or a dedicated `HandPosition` marker to make it easier to attach items.

## 2. Blueprint/Ghost Effect
**Objective:** Show a semi-transparent hologram of the completed wall.

### Changes
- **`scenes/building_block/wall_section.gd`**:
    - Add a `_blueprint_mesh` (MeshInstance3D).
    - Create a "Blueprint Material" (Blue/White, semi-transparent, perhaps with a grid/fresnel effect).
    - Logic to show the blueprint only when `completion_percent < 100.0`.
    - Fade out the blueprint as the actual wall grows.

## 3. Dynamic Audio Cues
**Objective:** Add spatialized sound effects for material delivery and building.

### Changes
- **`scenes/building_block/wall_section.gd`**:
    - Add an `AudioStreamPlayer3D` node.
    - Implement a `_play_sound(type: String)` method.
    - Trigger sounds in `request_add_material` and `request_build`.
    - Since no sound files exist, I will implement the *infrastructure* (nodes and code) and use placeholder paths/comments, or use a simple `AudioStreamGenerator` for procedural sounds if appropriate.

## Verification & Testing
- **Visual Check:** Walk around with each material type and verify they are visible and positioned correctly.
- **Ghost Check:** Verify that new wall sections show a blueish "ghost" wall that disappears once finished.
- **Audio Check:** Ensure the `AudioStreamPlayer3D` is triggered (can be verified with `print` logs if sounds are missing).
- **Multiplayer Sync:** Ensure all visual changes (ghosting, carried items) are properly replicated across all peers.
