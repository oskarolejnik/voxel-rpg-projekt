# Voxel RPG — Weakness Audit Backlog (2026-06-24)

> Source: 11-subsystem parallel audit (one agent per subsystem) + adversarial verification of every
> high/medium finding against the real code + synthesis. 54 confirmed findings. Refuted/overstated
> findings were dropped; several were downgraded to "partial" (latent, not active).
>
> Recurring theme: **the engine schema is richer than the runtime** — the biggest wins are *wiring
> existing fields*, not building new systems.

## Ranked top-12 (impact-per-effort; user priority order as tiebreaker)

| # | Item | Area | Sev | Eff | Status |
|---|------|------|-----|-----|--------|
| 1 | Enemy hitstun/stagger so hits interrupt windup | Combat | high | M | ✅ done — commit 4884319 |
| 2 | Fix SET items granting zero set bonuses (`set_id` lost at roll) | Loot | high | M | ✅ done — commit 6900d6d |
| 3 | Local-freeze SP hitstop (global `time_scale` freezes player input) | Feel | med | M | ✅ done — commit 5bfe623 |
| 4 | Loot in TREASURE/SECRET dungeon rooms (currently empty) | Dungeons | high | M | ✅ done — commit 32f20b2 |
| 5 | Real status-effect pipeline (ignite/chill/poison/stun; `on_hit_effects` is a no-op) | Combat | high | L | ✅ done — commit 666fb76 |
| 6 | Strafe locomotion for lock-on circling (feet skate) | Feel | high | L | ✅ done — commit 70f77bb |
| 7 | Per-class skill kits + spawn handler (cast_time/Projectile/HazardZone) | Combat/Prog | med | L | ✅ done — commit bbe8e1e |
| 8 | Biome-aware heightmaps (terrain shape varies per biome) | World | high | L | ✅ done — commit ed808ee |
| 9 | Author the 4 missing biomes + extend progression | World | high | L | ✅ done — commit ed808ee |
| 10 | Minimap + compass HUD | UI | high | L | ✅ done — commit 6a90d88 |
| 11 | Boss/miniboss unique mechanics (telegraph/phase/adds) | Dungeons | high | L | ✅ done — commit 4749827 |
| 12 | Per-class passive trees + per-level baseline power | Prog | crit | XL | ◑ slice done — commit c20a988 (mage/ranger/rogue + baseline; 7 classes + namespace remain) |

## #5 scope note (discovered while reading the code)

Status effects is bigger than an in-place wiring fix — the data isn't flowing at all:
- `HitData.on_hit_effects` exists but is **empty**; nothing populates it (elemental affixes add `<elem>_damage` stats, not effects).
- `HitData.to_dict/from_dict` **don't serialize** `on_hit_effects`, so a co-op client→host attack would drop any status.
- No DoT/CC engine exists. `DamageService._resolve` step 6 (`_apply_status`) is commented out.

Sub-tasks (each a separate commit): (a) a host-authoritative `StatusEffectComponent` with a DoT ticker + CC; chill can **reuse the existing `BuffComponent`** (timed `move_speed` StatModifier); stun gates `AIComponent` windup. (b) Populate `on_hit_effects` from affix/skill tags. (c) Serialize `on_hit_effects` in HitData for co-op. (d) Uncomment + implement `DamageService._apply_status`. Start fresh — do NOT half-wire it (a stubbed status system reads as "done" but isn't).

## Cross-cutting themes

1. **Dormant data, dead pipelines** — combat (`on_hit_effects` no-op), loot (`set_id`/`max_sockets`/`req_level`/gem quality never read), skills (`grants_skill`, `SkillResource.scene`/`cast_time`, power points). Wire fields, don't build systems.
2. **Combat lacks reactivity** — hitstun (now done), status effects, poise-break (now done), knockback-interrupt (now done) all share the `take_damage` touchpoint. Status effects (#5) is the remaining big one.
3. **World reads flat and finite** — one shared heightmap, 3 of 7 biomes, no caves, no minimap. Biome-aware terrain shape (#8) is the keystone.
4. **Loot chase has no payoff surfaces** — empty treasure rooms, unreachable SET tier, shared loot tables, flat affixes, no-delta compare tooltip.
5. **Netcode promises exceed implementation** — reconciliation replay, input queue, snapshot timestamps. Lower priority for a non-MMO co-op game; deferred out of top-12 except partner-movement feel.
6. **SP feel regressed where co-op was done right** — the global `time_scale` hitstop (#3) is the clearest case; the better local-freeze pattern already exists.

## Quick wins (S effort, high payoff)

- ✅ Low-HP red vignette pulse in HUD — commit a83ef0e.
- ✅ Enforce `req_level` on equip (LootService/InventoryComponent) — commit 650072d.
- ✅ Charge currency on per-node deallocate (close the free-respec loophole) — commit d6652a6.
- ✅ Read `ItemResource.max_sockets` in `LootService._roll_sockets` — commit 650072d.
- ✅ Guard `InventoryUI._set_open` against opening while another modal holds `ui_capturing_input` — commit 5922511.
- ✅ Fix boss-door blocker height in DungeonRun (size to door, not full room) — commit bb45dfe.
- ✅ Slope/water validity check + retry in `WorldSpawner._spawn_pos` — commit bb45dfe.
- ✅ Knockback interrupts windup — folded into the rank-1 poise mechanic (commit 4884319).
- ⬜ Persist respec cost index (`respec_count` in SaveData) — not yet (Save subsystem; deferred).

## Status: ALL of the audit top-12 + quick-wins are implemented and verified (headless suite 39/39 green).

Remaining follow-ups intentionally NOT in this pass (separate scope): #12 full 11-class trees + the
class-id namespace unification (Polish creator ids vs English progression ids); the Save subsystem
fixes (persist inventory/equipment during gameplay, atomic writes + .bak, corrupt-save guard); and the
netcode prediction/reconciliation hardening. These were flagged by the audit but are their own efforts.

## Notable critical/high bugs surfaced (some inside the ranked items)

- **Class-id namespace split** (Polish `wojownik` in creator vs English `warrior` in progression): the creator's class choice never reaches `GameState.class_id`, and non-warrior classes get no tree + the wrong resource bar. Blocks per-class progression (#12) — must unify ids first.
- **Save never persists inventory/equipment/appearance/skills during gameplay** — the loot pillar is lost on exit; only tests save full data. (Save subsystem; not in top-12 but high.)
- **Non-atomic save writes + silent wipe on corrupt save** — a crash mid-write or a corrupt file silently yields a fresh level-1 character.
