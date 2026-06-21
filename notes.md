# Marching Cubes Terrain: Implementation Roadmap (CPU + Threading)

Each item is a small step that leads into the next. The final implementation runs on
the CPU with multithreading. GPU compute shaders and manual buffer management are
intentionally excluded.

A few principles baked into the ordering:
- Prove correctness on the CPU before optimizing anything.
- The 2D pass is a throwaway learning tool. Do not polish it.
- Get a midpoint ("blocky") version working before adding interpolation, so you can
  separate topology bugs from positioning bugs.
- Fix same-resolution chunk seams before touching LOD.

---

## Phase 1 - 2D learning pass (marching squares, lightweight, throwaway)

- [x] Set up a 2D scratch scene where you can draw points, line segments, and text for debugging
- [x] Generate a 2D scalar field by sampling a noise function over a grid; store one value per grid point
- [x] Choose an isovalue (threshold) and visualize which grid points are inside vs outside (e.g. colored dots) to confirm the field looks reasonable
- [x] Find and copy the marching squares lookup table (16 cases)
- [x] For each cell, compare its 4 corners to the isovalue and pack the result into a 4-bit case index
- [x] Use the case index to find crossed edges; place vertices at edge midpoints (no interpolation yet) and draw the line segments to verify topology
- [x] Add linear interpolation along each crossed edge using the two corner values and the isovalue; confirm the contour smooths out
- [x] Stop here. Do not weld vertices or optimize the 2D version; it has done its job once the contour renders correctly

## Phase 2 - 3D correctness on the CPU (marching cubes, single block)

- [x] Generate a 3D scalar field by sampling 3D noise over a grid of points
- [x] Add a debug view (e.g. draw a dot at each grid point below the threshold) to sanity-check the volume
- [x] Find and copy the two marching cubes tables: the edge table and the triangle table (256 cases each)
- [x] For each cell, compare its 8 corners to the isovalue and pack the result into an 8-bit case index
- [x] Use the edge table to find crossed edges, place vertices at edge midpoints first, and emit triangles via the triangle table
- [x] Render the triangles unlit to confirm topology is correct before adding interpolation
- [x] Add linear interpolation along each crossed edge to position vertices precisely; confirm the surface smooths
- [x] Compute per-vertex normals from the gradient of the scalar field using finite differences (sample plus and minus along each axis, subtract, normalize)
- [ ] Add a debug mode that draws normals as short lines to verify they point outward
- [x] Build the final mesh (vertices, normals, indices) and render it lit
- [ ] Optional: weld shared vertices to reduce vertex count. Note this is for memory only; smooth normals already come from the field gradient

## Phase 3 - Make it terrain (still a single block)

- [x] Replace random noise with a terrain-shaped density function (e.g. a heightmap-style term for the ground surface combined with 3D noise for caves and overhangs); tune until it reads as terrain
- [x] Make the noise seed-based and deterministic so the same world coordinates always produce the same field (required for consistent streaming later)
- [x] Expose tuning parameters (frequency, amplitude, octaves, surface height) so you can iterate on terrain feel

## Phase 4 - Chunking on the CPU (single resolution)

- [ ] Decide a chunk size (cells per chunk) and a default render distance measured in chunks
- [ ] Generate a single chunk at an arbitrary world offset by sampling the global density function at that chunk's coordinates (a chunk is just a window into the infinite field)
- [ ] Implement the apron: when meshing a chunk, sample one extra cell beyond each boundary so border triangles align with neighbors. Verify two adjacent chunks have no crack between them
- [ ] Generate and display a grid of chunks out to the render distance around the camera, all on the main thread for now (expect a hitch; that is acceptable at this stage)
- [ ] Add chunk loading and unloading: create chunks that enter range as the camera moves, and remove chunks that leave it

## Phase 5 - Collision

- [ ] Generate a collision mesh for each chunk from its mesh data (full resolution or a simplified version, depending on your physics budget)
- [ ] Hook chunk collision into your physics engine and confirm the player and objects collide with the terrain
- [ ] Ensure collision meshes are removed when their chunk unloads

## Phase 6 - Threading (the core performance work, CPU only)

- [ ] Split chunk work into two halves: data generation (sample field, run marching cubes, produce vertex/index/normal arrays and collision data) and upload (create the engine mesh and buffers)
- [ ] Move data generation onto a worker thread or a job/thread pool so it runs off the game loop
- [ ] Keep mesh and buffer creation on the main (render) thread, consuming finished data from a thread-safe queue (most engines require mesh upload on the main thread)
- [ ] Confirm the game no longer stutters when chunks load or unload; profile to verify generation is off the main thread
- [ ] Add a per-frame budget so only N chunk uploads happen per frame, avoiding main-thread spikes

## Phase 7 - Initial load experience

- [ ] Add a loading scene or screen shown while the first ring of chunks generates
- [ ] Drive a progress bar from the count of completed vs requested initial chunks, read safely from the worker results
- [ ] Transition into gameplay once the starting area is ready

## Phase 8 - LOD with Transvoxel (final robustness)

- [ ] Define LOD bands: distance ranges at which chunks use lower resolution (larger cells)
- [ ] Generate lower-resolution chunks for distant bands using the same density function at a coarser sampling step
- [ ] Implement Transvoxel transition cells between chunks of differing resolution to close the cracks at LOD boundaries
- [ ] Address LOD popping (e.g. distance thresholds with hysteresis, or a short fade) so resolution changes are not jarring
- [ ] Confirm seams are gone across all LOD boundaries while moving through the world

## Phase 9 - Optional CPU-friendly optimizations (no GPU or compute shaders)

- [ ] Skip empty or full chunks early: if all corners of a chunk are entirely inside or entirely outside, generate no mesh
- [ ] Pool and reuse the vertex and index buffers per worker to reduce allocations and garbage
- [ ] Cache or persist generated chunk data so revisited areas reload without recomputation
- [ ] Optional mesh simplification or decimation for distant chunks if Transvoxel LOD alone is not enough
