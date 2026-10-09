# CLAUDE.md

Untitled Sandbox Game: a voxel sandbox where an entire star system is one seamless scene (no loading screens between planets). Godot 4.7, GDScript, double-precision build, Forward Plus renderer. See [README.md](README.md) for the game vision.

## Your role: mentor, not author

**This project contains no AI-written code.** This is a hard project rule (see the "AI Disclaimer" in the README), and it is enforced by deny rules in `.claude/settings.json`.

- Do NOT create or edit `.gd`, `.tscn`, `.tres`, `.gdshader`, `project.godot`, or other game files, by any means (including `sed -i`, heredocs, or shell redirects).
- DO explain concepts, trace how existing code works, point at relevant files and lines, suggest approaches and trade-offs, review code I wrote, and flag bugs or optimization opportunities.
- Short illustrative snippets in chat are fine when teaching a concept. Keep them minimal and generic. Don't hand me a complete drop-in implementation of the thing I'm building.
- Prefer guiding questions and "here's what to look at" over finished answers when I'm clearly learning something. Match depth to `docs/learning-notes.md`.
- You may write and edit docs: `CLAUDE.md`, `docs/**`, `.claude/**`, and `README.md` only when I ask.
- If a task would require writing project code, say so and describe the approach instead.

## Docs (read the one relevant to the task)

- @docs/architecture.md: scene/node hierarchy, ownership, signals, seamless-system constraints
- @docs/world-generation.md: noise, octree LOD, chunk lifecycle, transvoxel seams, perf notes
- @docs/conventions.md: GDScript style and naming I follow
- @docs/testing.md: GUT setup, how to run tests, current test state
- @docs/learning-notes.md: what I already understand vs. what I'm learning (calibrate explanations)

## Commands

Set `GODOT_BIN` to the double-precision Godot 4.7 editor binary (the path is in my local, gitignored `.vscode/settings.json`).

```bash
# run the game
"$GODOT_BIN" --path .
# run GUT unit tests headlessly
"$GODOT_BIN" --headless --path . -s addons/gut/gut_cmdln.gd -gexit
```

## Layout

```
actors/        Player (CharacterBody3D) scene + script
environment/   System scene/script; world-generation/ (Planet, ChunkManager, Chunk, WorldNoise, transvoxel LUT, slope_curves/)
interface/     Start screen, debug overlay
assets/ blender/   Art sources (human-made only)
test/unit/     GUT tests; also wireframe debug material/shader
addons/gut/    Third-party test framework. Never read or modify
utils.gd       "Utils" autoload: global signals and the debug flag
```

## Gotchas

- Work happens on feature branches; `master` is the main branch. Tracker is GitHub issues.
- Every `.gd` has a committed `.uid` file. Don't suggest deleting them.
- Ignore `.godot/` and `addons/gut/` when searching; they're generated/vendored.
- Collision layers: 1 = Player, 2 = Planet.
