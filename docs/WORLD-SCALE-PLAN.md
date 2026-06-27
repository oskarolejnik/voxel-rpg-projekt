# World-Scale Redesign — Master Plan

> Goal: Cube World exploration feel — world feels huge, player feels small, distant travel feels like adventure.
> Within hard constraints: co-op determinism (seeded host-authoritative gen), save round-trip, 4GB-laptop budget.
> Derived from a 6-analyst deep-analysis pass + measured baselines (below). Each phase is independently
> committable + verifiable via the `VOXEL_PROBE` harness.

## Measured baselines (PROBE)

- **Perf (`VOXEL_PROBE=stress`, 8 m/s traversal):** **~186–201 FPS** — render is NOT the bottleneck; huge headroom.
  But the build **`queue` stays 53–79 deep** and **`loaded` lags 15–41** during motion (vs 97 at rest):
  **streaming throughput is the bottleneck** (`MAX_IN_FLIGHT=3`, `MAX_FINALIZE_PER_FRAME=1`). No chunk leak
  (abandoned→0, settles to loaded=97). → We can afford much more view distance if we raise streaming throughput.
- **Scale (`VOXEL_PROBE=vista`):** a **fog wall at ~80 m** (deliberate — `fog_depth_end` tracks `far_dist` to hide
  the chunk cutoff). Low rounded hills, no distant peaks/landmarks. The short readable horizon is the dominant
  "world feels small" cause.
- **Trees (`VOXEL_PROBE=tree`):** modest Minecraft-ish trees (not towering), terraced terrain, hazy near horizon.

## The reframe

Making the world feel huge (bigger view distance, taller terrain, bigger biomes) **costs** the exact
streaming/render budget. Resolve by ordering: **(1) free perception wins, (2) cheap render/streaming headroom
that FUNDS distance, (3) spend it on the scale increases that need it, (4) terrain amplitude + landmarks (save-gated).**

## Invariants (every phase respects)

1. **Determinism** — `surface_height`/`_biome_band`/`_height_profile_blend`/`feature_hash` stay pure functions of
   `(world_seed, coords)`. Generation-constant changes (freq, amp, band width, jitter) are legal only if applied
   **identically on all peers** (they propagate via the seed). Render/scheduling levers (fog, LOD, finalize, in-flight,
   sort order, camera) touch zero generation math → inherently co-op-safe.
2. **Save** — `CHUNK_SIZE`/`VOXEL_SIZE` must NEVER change (rekeys every save). Anything that shifts `surface_y`
   (amp/base/freq/contrast/WORLD_HEIGHT) can float/bury saved voxel edits → **SAVE GATE before Phase 4**
   (bump `WORLD_GEN_VERSION`, batch as one). Pre-release with no saved edits → risk ~0.
3. **4GB** — only `WORLD_HEIGHT` and `near_dist` raise per-chunk RAM; everything else is O(1) or cheap FAR-ring.

---

## PHASE 1 — Free perception wins (player/camera/biome; ZERO perf, save-safe)

| # | File:line | From → To | Effect |
|---|-----------|-----------|--------|
| 1a | Player.gd `P_HEIGHT_M` | 1.80 → **1.45** | Player 3.6 → 2.9 world-voxels. Capsule auto-follows; floor_snap/auto-step unchanged. |
| 1b | Player.gd hurtbox (505-508) | hard 1.6/y0.9 → `P_HEIGHT_M*0.9` / `*0.5` | **MANDATORY with 1a** — else hits hit a phantom 1.6 m box. |
| 1c | Player.gd `step_height` | keep 0.55–0.6 | Must clear one 0.5 m voxel; don't scale down. |
| 1d | Player.gd `base_fov` | 66 → **72** | 66 is telephoto (enlarges player); smaller player can afford depth back. |
| 1e | Player.gd boom `spring_length` | 4.8 → **6.0** | Cheapest "huge world" lever, zero voxel cost. |
| 1f | Player.gd `boom_out_speed` | 5.0 → **7.0** | Longer boom auto-shortens near slopes; faster recovery keeps pulled-back feel. |
| 1g | Player.gd `cam_height` | 2.6 → **3.0** | Player lower in frame, more vista. |
| 1h | VoxelWorld.gd `BIOME_BAND_METERS` | 700 → **1200** | Biomes become 1200 m regions — fixes "transition too fast". (generation const) |
| 1i | VoxelWorld.gd `BIOME_BORDER_JITTER_M` | 90 → **140** | Keeps border organicism proportional. (generation const) |
| 1j | Player.gd `sprint_speed` | 10 → **8** | Eases streaming overrun + makes distance feel larger. |

Verify: `vista`/`gold` before/after (player smaller, horizon deeper), `walk` (stuck-frames don't rise).

## PHASE 2 — Cheap render headroom that funds distance (save-safe, zero determinism risk)

- **2A** — fog tune (hide hard cutoff; near-free) + `MAX_FINALIZE_PER_FRAME` 1→**2** (halve pop latency).
- **2B** — forward-bias build sort (spend in-flight slots on chunks seen first) + 1-chunk predictive look-ahead.
- **2C** — `MAX_IN_FLIGHT` 3→**5** (PROFILE-GATED on the shared WorkerThreadPool; revert to 4 if physics/audio hitch).

Verify: `stress` FPS steady + zero leak (gate for 2C).

## PHASE 3 — Funded distance (save-safe; needs Phase 2 first)

- LOD3 ultra ring `ultra_dist=10` (160 m), `LOD_STEP_ULTRA=4` (8×8 cells, <1 ms, ~4 MB VRAM, no collision).
- `far_dist` 5→**7** (112 m mid-quality; needs `MAX_IN_FLIGHT=5`).
- Frustum prefilter for FAR/ULTRA rings only (never NEAR) — halves forward-travel build load.
- Fog `fog_depth_end` → ~150–180 to match new horizon.

Verify: `vista`/`gold` (distant silhouettes at 112–160 m), `stress` (FPS holds, no leak).

## PHASE 4 — Funded terrain amplitude + landmarks (SAVE-GATED, determinism-uniform)

- **4A terrain shape:** `_noise.frequency` 0.007→**0.004** (wider mountains, free); mountains `freq_mul` 1.3→0.9;
  contrast forest 1.6→2.0 / mountains 1.9→2.3; `WORLD_HEIGHT` 96→**128/160** (only real RAM lever — profile);
  amps mountains/frosthelm/volcanic up (only after ceiling raised).
- **4B landmarks:** FAR-ring tree pass (`_build_coarse` trees, no collision) — world no longer bald past 48 m;
  tree tiers ~2× taller; rare GIANT trees (beacon); biome-scaled `TREE_PROB`; emissive obelisk on dungeon entrances.

Verify: `gold`/`vista` (mountains tower, trees 6–9× player, skyline beacons), `stress` (meshing holds; drop
WORLD_HEIGHT to 128 if FPS regresses). **SAVE GATE: bump WORLD_GEN_VERSION, batch 4A.**

---

## Commit sequence

0 baselines → 1 player/camera/biome → 2A fog+finalize → 2B sort+lookahead → 2C in-flight (profiled) →
3 LOD3+far_dist+frustum → 4A terrain (save-gated) → 4B trees+landmarks.

Success = `gold` shows progressively smaller player + deeper horizon at each phase, while `stress` FPS never
regresses below the ~190 baseline and chunk-leak stays zero.

Files: `src/Player.gd`, `src/world/VoxelWorld.gd`, `src/world/Chunk.gd`, `src/world/DungeonEntrance.gd`,
`src/DayNight.gd`/`src/Main.gd` (fog).

---

## OUTCOMES (implemented)

Branch `world-scale`. Baselines pinned at `PROBE_SEED=1337`.

| Phase | Commit | Result | Verify |
|---|---|---|---|
| Plan | d09680d | analysis + baselines | — |
| 1 player/camera/biome | 74a2e13 | player 1.8→1.45 m, FOV 66→72, boom 4.8→6.0, cam_height 2.6→3.0, sprint 10→8, biome band 700→1200 m | A/B gold: player smaller + deeper vista; walk: traversal safe (isolated the stick to biome-terrain, not physics) |
| 2 streaming | cdd1007 | forward-bias build order | **Finding: machine is CORE-BOUND** — MAX_IN_FLIGHT 3→5 halves FPS (190→90). Constants kept; prioritize leading edge instead |
| 3 view distance | 2545ada | far_dist 5→7 (80→112 m); fog auto-recedes | stress FPS holds ~150, no leak |
| 4A terrain | fc984b7 | noise freq 0.007→0.004 (wider), mountains amp 78→100 + freq_mul 1.3→0.9 + contrast 1.9→2.3, WORLD_HEIGHT 96→128 (peaks ~61 m) | gold: mountains tower over player; FPS holds (surface-bound fill = cheap); walk smooth |
| 4B trees | b62139e | trunk 8/10/12→10/14/18, rare giants 22-28 (landmarks), biome density (verdant ×3 … volcanic ×0) | FPS holds; player dwarfed by terrain+trees |

### Key engineering finding
Render perf is NOT the bottleneck (~150-190 FPS, RTX 3050). **Streaming is CORE-BOUND**: the
WorkerThreadPool is saturated by 3 workers + main on ~4 cores, so adding threads *regresses*
(oversubscription). The lever for more view distance is therefore **faster per-chunk meshing**, not
more concurrency. (Measurement caveat: the stress `loaded` metric is dominated by run-order/thermal
state — the 2nd back-to-back run is always worse regardless of variant.)

### Deferred (need a meshing-speed pass first, or are larger features)
- **LOD3 ultra ring (~160 m silhouettes):** ~2× tracked chunks — the core-bound streamer can't fill it
  while moving. Unlock by speeding up meshing (greedy meshing / fewer faces) first.
- **FAR-ring trees:** world is currently bald past the 48 m NEAR ring (features are NEAR-only). Add a
  trees-only pass to `_build_coarse` so forests reach the horizon.
- **Obelisk/spire landmarks** on dungeon entrances (mesh-based, cheap) — clearest "go there" beacon.
- **Meshing-speed pass** (the real unlock): greedy meshing, noise caching — funds the above on 4GB.

### Save note
Phases 4A shift `surface_y` (terrain regen). Character saves (level/loot/inventory) are unaffected;
only saved voxel EDITS on an old world float — acceptable pre-release. Start a fresh world to see it.

---

## MESHING-SPEED PASS — findings (no code kept; the safe levers don't move it)

Profiled the chunk worker (gen vs mesh, `Time.get_ticks_usec`):

- **mesh ≈ 400 ms CPU/chunk at low contention** (gold@spawn 447 ms, walk 393 ms), **gen ≈ 120 ms**.
  Under the fast-travel stress this inflates to ~625 ms (≈ +180 ms preemption — 3 workers + main on ~4
  cores). Queue-drain rate (~3.7 chunks/s) ≈ per-chunk wall-time ÷ 3 workers — so the per-chunk mesh CPU
  **is** the streaming limiter.
- **Tried + reverted (zero measurable gain):**
  - *Per-column loop bound* (skip air above `_colmax` instead of full WORLD_HEIGHT) — the skipped air
    iterations are cheap; the face-generation work dominates.
  - *`MeshBuilder`* (SurfaceTool → direct PackedArrays, no vertex-dedup hashing) — rendered identically
    but mesh time unchanged (625 vs 607 ms). So the cost is **not** vertex accumulation.
- **Conclusion:** the ~400 ms is **face GENERATION**, not vertex bookkeeping — dominated by the fine-leaf
  clusters (thousands of sub-voxel faces/forest-chunk; Phase 4B's denser+taller trees *raised* this) plus
  per-voxel `_solid_color`/`_is_face_visible` noise sampling. **Greedy meshing is blocked** by per-voxel
  continuous tint (faces can't merge without flattening the look).

### What would actually unlock it (each a trade-off / bigger lift — product decisions)
1. **Simpler far/forest leaf rendering** (billboard or coarse leaf blocks past N m) — biggest win, mild
   visual change. Pairs naturally with the deferred FAR-ring trees (coarse leaves only).
2. **Native (GDExtension) mesher** for the solid surface — removes GDScript per-face overhead; large lift.
3. **Accept the far-edge lag**: ship the ultra ring / far trees knowing the distant edge fills a beat
   behind under sprint (fog hides it) — no code-speed needed, just tuning.
4. **Greedy meshing** only if the terrain moves to per-*type* (not per-voxel) color — a look change.

The streamer is therefore **core-bound + face-generation-heavy**; the safe tuning levers are exhausted.
Further view-distance/forest-horizon gains need one of the above, not more parameter tuning.
