# Art Direction Bible — "Storybook Voxel"

> Visual identity for the voxel action-RPG. Derived from an 8-subsystem art-direction
> audit (character, enemy, terrain, micro-detail, HUD, VFX, animation, lighting) synthesized
> into one cohesive look. This is the **executive creative reference** — every visual change
> is gated against the pillars below.
>
> **Status:** authored 2026-06-25. Implementation tracked on the `visual-overhaul` branch.
> Most changes need an in-engine pass against the AGX + glow knee before merging to `main`.

---

## The Look

**Storybook Voxel** — a hand-painted, sun-warmed Cube World silhouette rendered with modern
stylized depth: chunky readable forms, sub-voxel detail on the things you look at closest
(faces, trunks, armor), saturated-but-disciplined color, and one luminous golden-hour
atmosphere that makes every place feel alive.

The single unifying idea is **painterly volume without textures**: every surface earns its
richness from vertex color + cheap GPU shading (hemi ambient, value-contrast, rim, AO)
rather than maps, and every entity earns identity from **silhouette + color + glow** rather
than fidelity. Warm key light, cool fill, gentle bloom, and atmospheric depth fog are the
constant "house style" that binds player, enemy, terrain and UI into one world. The premium
feel comes from **cohesion and motion-life** (breathing, secondary motion, juiced impacts),
not from polygon count — which is exactly what the 4 GB target can ship.

---

## Visual Pillars (every change is gated against these)

1. **READABLE FIRST.** Silhouette, value contrast and color must communicate class, threat
   tier, and biome *from a distance* before any detail reads. Never let glow/bloom/saturation
   blow out a silhouette — respect the existing AGX + glow knee (keep emissives subtle, whites
   pre-dimmed).
2. **IDENTITY THROUGH COLOR + SILHOUETTE + GLOW, NOT FIDELITY.** Classes, enemies and biomes
   are distinguished by palette, shape accents and emissive color — the cheapest, most
   co-op-safe, most deterministic levers — never by texture detail the voxel pipeline can't carry.
3. **PAINTERLY VOLUME, ZERO TEXTURES.** All surface richness is vertex-color + cheap per-pixel
   GPU shading. This is the proven house technique already in `terrain.gdshader` — extend it to
   enemies and props rather than inventing a new material language.
4. **ONE WARM, ALIVE ATMOSPHERE.** A single golden-hour-leaning lighting identity (warm key,
   cool fill, gentle bloom, depth-fog aerial perspective, biome-tinted fog/ambient) is the
   connective tissue. Atmosphere is the cheapest path to "alive" and must read as **place**,
   not filter.
5. **EVERYTHING BREATHES.** No static statues, no stamped FX. Procedural idle life, secondary
   motion, anticipation/overshoot, and juiced impact feedback are mandatory.
6. **ONE CRAFTED OBJECT.** HUD and panel UIs share a single wood-and-gold storybook frame so
   the interface feels carved from the same world, never dropping into engine-default gray.

---

## Signature Moves (the recognizable hooks)

- **Class-readable hero.** Each class reads instantly at distance via palette + projecting
  shoulder pauldrons scaled by `armor_weight` + a class-colored emissive accent (mage cyan
  staff-crystal, warrior crimson blade-edge, ranger green fletching) + per-class headgear
  silhouette. **The accent-glow color is the class's signature hue, echoed in their VFX and
  resource bar** — one color identity per class across model, UI and combat.
- **Golden-hour god-rays on the shipping preset.** Warm depth-fog sun-scatter halo at
  dawn/dusk that works *without* volumetric fog (recovered for free on the 4 GB LOW preset),
  so "golden hour" becomes the game's beauty-shot moment.
- **Moonlit navigable night.** Tinted blue ambient *color* + a travelling pool of warm light
  that follows the player at night — turns the current flat-dark-blue void into an
  atmospheric, lantern-lit world.
- **Biome-as-place.** Each biome is a distinct atmosphere (Frosthelm = cold blue haze,
  Emberwaste = warm ash glow) driven through fog color, ambient tint *and* palette together —
  you know where you are from the horizon silhouette alone.
- **Juiced kills + swept blade arcs.** The kill gets a light-pop + flash + rising energy wisp
  + camera punch, and melee swings leave a real bright-leading-edge swept arc — every hit and
  kill feels weighty and earned.

---

## Palette & Lighting

### Per-biome (terrain tint mul + fog/ambient tint + light warmth)

| Biome | Terrain tint (×albedo) | Sat | Fog / atmosphere |
|---|---|---|---|
| **Verdant** (forest) | `(1.00, 1.02, 0.96)` | 1.06 | neutral `(0.92,0.96,1.0)` — **calibration anchor, leave true** |
| **Plains** | `(1.05, 1.04, 0.86)` | 1.10 | warm hazy gold, sunlit and open |
| **Swamp** | `(0.80, 0.92, 0.74)` | 0.85 | thick low green-grey fog, dimmer key, oppressive |
| **Emberwaste** (desert) | `(1.16, 0.92, 0.70)` | 1.18 | warm ash `(1.0,0.72,0.45)`, hot low sun (keep R below glow knee) |
| **Frosthelm** (snow) | `(0.88, 0.94, 1.05)` | 0.78 | cold blue haze `(0.78,0.86,1.0)`, pale flat winter light |
| **Mountains** | `(0.92, 0.93, 0.97)` | 0.92 | clear thin air, crisp shadows, cooler fog |
| **Volcanic** | `(1.10, 0.74, 0.66)` | 1.15 | warm ember underglow in fog, dark sky (cap R×sat) |

### Time-of-day (keyframed in `DayNight.gd`, extend)

- **Night** — ambient *color* `(0.30, 0.38, 0.62)` blue moonlight, floor energy `0.12 → 0.16`,
  plus a warm follow-light `(1.0, 0.85, 0.55)`.
- **Dawn / Dusk** — warm key `(1.0,0.55,0.32)` / `(1.0,0.45,0.25)`, `fog_sun_scatter`
  `0.08 → ~0.34` for god-rays.
- **Day** — warm-white `(1.0, 0.95, 0.85)`.

### Glow (premium luminous range — **highest-risk knob, verify in engine**)

LOW preset: intensity `0.2 → 0.35`, bloom `0.1 → 0.18`, hdr_threshold `1.0 → 0.85`, blend
SCREEN. Re-check that snow/sand/water do not blow out (SNOW is pre-dimmed to 0.90 — that is
the safety margin).

---

## Ranked Roadmap

Order overrides the lead's stated priority where evidence shows a bigger win-per-effort.
Every item is pure code/data (no new assets) and co-op-safe; all need a Godot verify pass.

| # | System | Why this rank | First concrete step |
|---|---|---|---|
| **1** | **Lighting & atmosphere** (was lead #7) | Cheapest path to "alive"; `DayNight` already authors the fog/ambient keyframes and `ambient_light_sky_contribution=0.6` is set — wiring is half-done. One file, zero assets, deterministic, and it lifts *every* other subsystem for free. | `DayNight.gd`: add `_AMBIENT_COLOR` + `_FOG_SUN_SCATTER` keyframe arrays, write `_env.ambient_light_color` / `_env.fog_sun_scatter`, raise night floor. Then glow lift in `Main.gd` + `GameSettings` LOW preset. |
| **2** | **Character models** (lead #1) | All 8 classes render the identical green-tunic/red-cape body — zero class fantasy on the most-looked-at object. `ClassResource.armor_weight` + `CharacterAppearance.body_color` already exist as **dead data**. Pure code/data, load-time, co-op-safe. | `Player.gd`: `_class_palette(cls)` → store `_pal` in `_build_voxel_character` before sculpting; replace hardcoded `_sculpt_*` const Colors with `_pal` lookups; consume `body_color` + `armor_weight`. |
| **3** | **Combat feel / VFX** (lead #2) | Core-loop payoff has the weakest VFX. `FeelFX.gd` is a clean pooled system → localized, low-risk, asset-free (gradient/curve textures generated in code). | `FeelFX._make_spark`: add `GradientTexture1D` color-ramp + `CurveTexture` scale-curve (built once in `_ready`); death light-pop + flash + rising-wisp from `Enemy._spawn_death_burst`. |
| **4** | **HUD / UI** (lead #3) | HUD is already a crafted wood-gold piece, but inventory/skill-tree drop into engine-default gray — the most jarring identity break. HUD palette constants already exist to seed a code-only Theme. | New `src/ui/UITheme.gd` (Theme from HUD wood-gold constants); apply in `InventoryUI._build_panel` and `SkillTreeUI._build_panel`; hotbar ready-glow. |
| **5** | **Enemy redesign** (lead #4) | Contains a real **bug** (boar/deer render as humanoid goblins) + threat-tier readability + biome identity. Larger surface; bug-fix + threat tier are pulled out as quick wins. | `Enemy.gd`: add `&"beast"` kind for `[boar, deer]`, `_build_silhouette_beast()` (horizontal quadruped + 4 leg pivots, back pair phase-offset π). |
| **6** | **Terrain shape** (lead #5) | Biome **color** fix is a quick win; full terrain identity (biome-aware `_block_for`, cliff terracing, rivers, landmarks) is larger structural work touching both LOD paths. | `Blocks.biome_modulate`: 4 elif branches (plains/swamp/mountains/volcanic); `Chunk._block_for` branch surface block by cached biome byte. |
| **7** | **Micro-voxel detail** (lead #6) | Tree trunks (every tree, eye-level) are the worst "big cube" offender; rocks second. Proven `_emit_leaf_cluster` pattern fits the 1-draw-call/chunk budget but needs face-budget tuning. | `Chunk._build_mesh`: route surface WOOD to `_emit_trunk_cluster()` (TRUNK_SUB=2, radial cull + root flare + bark tint, gated by a face budget). |
| **8** | **Polish** (lead #8) | Highest-effort, highest-novelty, lowest readability-per-hour: cloud/star sky shader, weather, cave/dungeon lighting. The "wow finish" once identity + atmosphere are solid. | New `src/sky.gdshader` (clouds + hash starfield + moon, driven by a `night` uniform from `DayNight`). |

---

## Quick Wins (high-impact, low-risk, pure code/data — ship first)

1. **Per-biome terrain color** — 4 missing `elif` branches in `Blocks.biome_modulate`
   (plains/swamp/mountains/volcanic); `clampf` already guards the glow knee. *Done first.*
2. **Free golden-hour god-rays** — `_FOG_SUN_SCATTER` keyframes in `DayNight`, write
   `_env.fog_sun_scatter` (~0.34 dawn/dusk, 0.08 else). Zero GPU cost.
3. **Moonlit night ambient color** — `_AMBIENT_COLOR` array + `_env.ambient_light_color`,
   night floor `0.12 → 0.16`. The `sky_contribution=0.6` plumbing is already in place.
4. **Glow lift to premium range** — `Main.gd` glow knobs (behind the LOW preset). *Highest
   risk — engine-gate this one.*
5. **Per-class palette** in `Player.gd` — consume the dead `body_color` + `armor_weight`.
6. **Spark color-ramp + scale-curve** in `FeelFX._make_spark`.
7. **Enemy living idle** — phase-seeded breath + weight-shift instead of lerp-to-zero.
8. **Element-colored emissive enemy hit flash** (`Enemy._flash_hit`).
9. **Code-only shared UI Theme** from the HUD wood-gold constants.

---

## Biggest Risks

- **No live Godot verification (current session).** Nearly every visual change needs in-engine
  confirmation against the AGX + glow knee. The glow lift (threshold 0.85) is riskiest — it can
  blow out snow/sand/water silhouettes and feed bloom on emissives tuned below the old knee of
  1.0. **Mitigation:** ship glow behind the `GameSettings` preset, change one knob at a time,
  use the "gold probe shot" the code comments reference as the gate.
- **Glow/emissive overbright cascade.** Glow lift + class-accent emissives + brighter night +
  god-ray scatter compound and can collectively wash out readability. **Mitigation:** keep each
  emissive subtle (energy ~2.0 like existing eye-glints); sequence lighting *before* new
  emissives so the knee is calibrated first.
- **Generation determinism in co-op.** Terrain + any seeded placement must be pure functions of
  position/seed so all clients and both LOD paths agree. **Mitigation:** derive from existing
  `feature_hash`/`world_seed`, never per-client RNG; verify NEAR and FAR meshers sample the
  same `surface_height`.
- **Perf on the 4 GB target.** Sub-voxel trunks/rocks multiply faces; always-on threat lights +
  night follow-light add draw cost; sky shader adds fragment work. **Mitigation:** enforce face
  budgets (like the existing `LEAF_FACE_BUDGET=9000`), cap always-on lights, keep volumetric fog
  OFF (god-rays via free depth-fog scatter).
- **Scope/cohesion drift.** Eight subsystems × dozens of improvements risks a grab-bag.
  **Mitigation:** gate every change against the pillars; lock the per-class signature-color
  mapping early (model + UI + VFX share it); resist novelty items (weather, sky shader) until
  identity + atmosphere are cohesive.
- **Engine version gap (Godot 4.7, ~4 minor beyond LLM baseline).** Environment / Decal /
  Sky-shader and `glow_blend_mode` APIs may have changed defaults (glow defaults changed in 4.6).
  **Mitigation:** verify each Environment/Decal/ShaderMaterial property against
  `docs/engine-reference` before relying on it.

---

*One color identity per class, one warm atmosphere, one crafted frame. Make it alive.*
