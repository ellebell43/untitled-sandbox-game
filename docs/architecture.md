# Architecture

## Goal

One scene (`environment/system.tscn`) holds a whole star system. The player moves between planets with no loading screen, so planets, their gravity, and their terrain streaming all coexist in a single live scene tree.

## Node/ownership hierarchy

```
System (environment/system.gd, Node3D)
├── Planet × N (environment/world-generation/planet.gd)
│   ├── GravityArea (Area3D) → GravityShape (sphere)
│   └── ChunkManager (added in code, child of Planet)
│       └── Chunk × many (added in code, MeshInstance + collision)
└── Player (actors/player.gd, CharacterBody3D)
```

- **System**: waits for the spawn planet's first batch of chunks (loading progress bar), then un-freezes the player (`ready_for_player`).
- **Planet**: owns the `WorldNoise` and creates its `ChunkManager` in `_ready()`. Rotates itself each physics frame around `rotation_axis`. Its `GravityArea` tells the player when they enter/leave (`current_world`) and flips `is_current_world`.
- **ChunkManager**: created in code (`ChunkManager.new(...)`), positioned at `-total_volume / 2` so the planet's centre sits at the Planet node's origin. Owns all chunks for that planet.
- **Chunk**: one cube of terrain at one LOD, owns its mesh data and thread id.
- **WorldNoise** (`RefCounted`): pure scalar-field function; no scene presence. Shared by the planet's spawn search and its chunks.
- **Player**: has `spawn_world: Planet`, `current_world`, `fly_mode`, `allow_inputs`. Must be below all Planets in the tree, because `Planet.get_valid_spawn_point()` needs the planet ready first.

## Planet size

`size` (export, 7–19) is the octree depth. `volume_length = CHUNK_SIZE * 2^size`; `floor_distance` (surface radius) is `volume_length / 2 - 500`; gravity extends 1000 m past the surface. Terrain can rise up to ~2000 above the surface radius. See the table in `planet.gd`.

## Signals / global state

`Utils` (autoload, `utils.gd`) is the global signal bus plus `Utils.debug`:
- `chunk_task_count_found(total)`: first-pass chunk total (spawn world only) → progress bar max
- `chunk_task_completed(n)`: progress updates
- `chunk_generated(gen_time)`: timing/debug

## Current-world vs. distant-world

Only the planet the player is inside gravity range of (`is_current_world`) runs full octree LOD refinement around the player. Other planets collapse to a single coarse root chunk (see `_octree_iterate` in `chunk-manager.gd`). This is how multiple planets stay affordable in one scene.

## Planned (not built yet)

Seasons/axial tilt, survival metrics, gardening, ships, teleporters, inter-system probes, multiplayer (server hosts one star system), see README. Keep multiplayer in mind when adding global state: prefer data owned by Planet/System nodes over autoload singletons.

## Open questions / known rough edges

(Edit as decisions are made.)
- `Planet.get_valid_spawn_point()` recurses and has an ordering requirement (player after planets).
- Planet rotation is applied directly to the node, so anything standing on it needs to rotate with it. Document the chosen approach here when settled.
- `WorldNoise.USE_GRADIENT` biome colouring is marked WIP/broken.
