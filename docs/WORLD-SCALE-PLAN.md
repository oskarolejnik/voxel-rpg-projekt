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
