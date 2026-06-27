# Cube-World World-Gen Redesign — Plan

> Goal: replace "noise-function Minecraft" with designed Cube-World spaces — strong biome identity,
> massive iconic forests, huge stylized trees, cohesive large-scale terrain, rivers, readable
> silhouettes — AND make streaming seamless. Derived from a 6-agent research pass (Cube World design
> + procedural technique + perf/C++ path) grounded in a code audit. Each phase = a committable milestone,
> verified via the `VOXEL_PROBE` harness (vista/gold/tree shots + stress FPS/streaming log).

## Code audit — the root causes (verified)

- **Biomes are concentric distance rings:** `get_biome = BIOME_PROGRESSION[floor((|x,z|+warp)/1200)]`
  (`VoxelWorld.gd:522`). Radially symmetric → every direction gives the same biome sequence. **This is
  the "system-like / fragmented / no cohesion" cause.** (Difficulty also keys off distance via
  `distance_tier()` — that part is Cube-World-correct and stays.)
- **Terrain is raw FBM, no warp:** `surface_height` feeds world coords straight into FBM × contrast
  (`:352,359`) — axis-aligned, mean-clustered → "noisy / grid-obvious / too flat in the wrong way".
- **Trees = per-voxel fine-leaf clusters** (`Chunk.gd` `_emit_leaf_cluster`, `LEAF_SUB=2`): ~1000-1500
  faces/tree, ~9000/forest-chunk — simultaneously the **#1 measured perf cost** AND off-style (Cube World
  canopies are solid single-color blobs).
- **No rivers** (only sea-level lakes where terrain dips).

## The perf decision: GDScript-first, NOT C++

Cube-World trees are *by definition* low-face blobs, so the on-style art change **is** the perf fix:
~9000 → ~300 faces/forest-chunk (30-60×) drives mesh time from ~400 ms toward the ~120 ms gen floor.
C++ would speed up an operation we'll have deleted — and can't even build here (only MinGW GCC 6.3.0,
no SCons/godot-cpp). Every terrain technique below adds only *noise samples/column* (zero faces). The
only face-count change *reduces* faces. The redesign is perf-positive end to end. (Re-profile after
Phases 1+4; if dense forests still exceed budget, C++ becomes a separate, toolchain-gated task.)

## Phases (cheap-high-impact first)

| Phase | What | Save |
|---|---|---|
| **1 — Big-blob canopy** | Replace fine-leaf clusters with a few large flat-tinted boxes/tree (Cube-World blobs); trees 16-28 voxels + rare giants. Fixes streaming (#1) AND generic trees. | **safe** (geometry/color only) |
| **2 — Domain warp + redistribution** | `_warp_noise` (freq 0.002) warps coords before sampling (WARP_AMP 80 m); `pow(e, exponent)` per profile → broad flat valleys + organic flowing landforms. | breaking |
| **3 — Ridged multifractal + mountain mask** | Hand-rolled multifractal on warped coords + low-freq `_mountain_mask` → a few iconic massifs, broad base + dramatic crown (not uniform spikes). Bundle save-bump with P2. | breaking |
| **4 — Tint→shader + greedy terrain meshing** | Move per-voxel tint to fragment shader; quantize color so flat runs merge; greedy-mesh terrain; Y-loop clamp to surface+canopy. Buys headroom for dense forests. | safe |
| **5 — Region biomes + jittered forests** | Replace radial `_biome_band` with warped Worley/Whittaker 2D region map (keep `distance_tier` for difficulty); macro continent field; jittered-grid tree placement + clearings. **The cohesion fix.** | breaking |
| **6 — Rivers + landmarks (deferred)** | Coarse-grid downhill flow network carving valleys + lakes; landmarks on riverbanks/ridges. No 3D overhangs (breaks heightmap + CPU budget). | breaking |

## Per-complaint → fix

- *too noisy / grid-obvious* → domain warp (P2).
- *too flat in the wrong way* → redistribution `pow` exponent (P2).
- *mountains Minecraft-blocky* → ridged multifractal + mountain mask + wider freq_mul (P3).
- *transitions abrupt / system-like* → 2D region biomes replacing radial rings (P5).
- *forests lack identity / generic trees* → big-blob biome-archetype canopies (P1) + jittered placement + clearings (P5).
- *streaming too slow* → big-blob canopies cut faces 30-60× (P1) + greedy terrain meshing (P4).

Success: P1 forest-chunk mesh-ms drops ~10×+ and the player moves freely (the #1 complaint); P2-3 vistas
read as flowing designed landforms + bold massifs; P5 a top-down map shows tiled regions, not onion-rings.
Trade-offs accepted: two save-version bumps (P2+3 batched, then P5); rivers last; abrupt-but-organic borders
kept (Cube-World-faithful). Engine note: all techniques use only FastNoiseLite + pure GDScript (near-zero
4.7 API risk); verify FastNoiseLite cellular enum names before the P5 region work.
