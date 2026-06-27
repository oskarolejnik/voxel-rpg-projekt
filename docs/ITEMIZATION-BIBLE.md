# Itemization & Loot Bible

> The design + technical architecture for the loot/equipment expansion: 100+ items, 7 rarity
> tiers, class itemization, equip effects/procs, **visible equipped models**, 6 class sets, and
> per-biome/dungeon/boss loot tables. Derived from a 6-agent deep analysis of the existing system.
>
> **Status:** authored 2026-06-27. Implementation tracked on the `visual-overhaul` branch, phase
> by phase, each verified in-engine and committed.

---

## Governing principles (read first)

The existing system is a clean, deterministic, save-safe skeleton with three load-bearing seams:
a **definition/instance split** (`ItemResource` read-only from `ItemDB` + `ItemInstance` lightweight
with a `seed` that fully reconstructs affixes), a **single stat funnel** (everything becomes a
`StatModifier` → `InventoryComponent.collect_modifiers` → `StatsComponent.get_stat`), and
**host-authoritative loot rolling** (`RNGService.loot` gated by `NetManager.has_state_authority`).

The expansion is **additive** and obeys these rules everywhere:

1. **Definition-side first.** Add to `ItemResource`/`SetResource`/`EffectResource` (definitions are
   never serialized — instances store only `base_id`) → **zero save cost**.
2. **Append-only enums.** `Rarity` and `Slot` are raw ints in saves. Appending is the *only* safe
   edit; reordering silently remaps every saved item. Invariant comments live at both enums.
3. **Every new instance field** goes in **both** `to_dict` and `from_dict` with a default-tolerant
   `get` (the `req_level` back-compat precedent). `SAVE_VERSION` stays 1 (additive).
4. **Three RNG lanes, strictly separated:** *what/whether* drops on `RNGService.loot` (host-only,
   fixed draw order rarity→slot→base_id→seed); *affix values* on the per-item LOCAL rng seeded by
   `_mix_seed` (client reproduces from seed alone); *proc chance* on `RNGService.combat` (host-only).
5. **Visuals are a pure function of replicated state** (`{base_id, rarity}`), never client-rolled.
6. **Incremental + lazy.** Rebuild only the changed pivot on an equip event; generate gear meshes
   from code on demand; pre-index `ItemDB` by slot/class to kill O(n)-per-drop scans.

---

## 1. Rarity — 7 tiers

Final enum (append-only): `COMMON=0, UNCOMMON=1, RARE=2, EPIC=3, LEGENDARY=4, SET=5, MYTHIC=6, ANCIENT=7`.

**Set reconciliation:** `SET` stays index 5 (a guaranteed full-set drop), but **membership is
decoupled from tier** — a set is assigned whenever the rolled base's `set_id` is non-empty, so a
Mythic-tier set piece is expressible. **Rarity = power axis, `set_id` = membership axis; they compose.**

Grow the six rarity-indexed `const` arrays in `LootService` to length 8:

| Tier | 0 Com | 1 Unc | 2 Rare | 3 Epic | 4 Leg | 5 Set | 6 Myth | 7 Anc |
|---|---|---|---|---|---|---|---|---|
| `TIER_MULT` | 0.7 | 0.85 | 1.0 | 1.15 | 1.25 | 1.0 | 1.4 | 1.6 |
| `AFFIX_COUNT` | 1 | 2 | 3 | 4 | 4 | 3 | 5 | 6 |
| `SOCKETS` | 0–0 | 0–1 | 1–1 | 1–2 | 2–2 | 1–1 | 2–3 | 3–3 |
| `WEIGHTS` | 50 | 30 | 14 | 5 | 1 | 0 | 0.2 | 0.04 |
| `COLOR` | grey | green | blue | purple | orange | turquoise | **crimson** `(0.92,0.16,0.22)` | **gold-white** `(1.0,0.86,0.45)` |
| name | — | — | — | — | — | — | Mityczny | Prastary |

Per-tier character: RARE = first enchant + drop beam; EPIC = first particles + 1 effect-eligible;
LEGENDARY = unique MORE (generalize gate `== LEGENDARY` → `>= LEGENDARY`); MYTHIC = 5 affixes,
crimson aura, 1 effect + 1 proc; ANCIENT = 6 affixes, radiant particles + ground halo (the chase item).
`LootDrop.gd` replaces hardcoded `0..5` clamps with `0..RARITY_COLORS.size()-1` so the tiers auto-scale.

---

## 2. Slots & weapon classes

Two enums move in lockstep, **append-only**:

- `ItemResource.Slot`: `…MATERIAL=7, GLOVES=8, SHOULDERS=9, BELT=10, CLOAK=11, AMULET=12`.
- `InventoryComponent.EquipSlot`: `…TRINKET_2=6, GLOVES=7, SHOULDERS=8, BELT=9, CLOAK=10, AMULET=11`
  (`EQUIP_SLOT_COUNT` 7 → 12).

**Ring/charm/relic are NOT new slots** — author as `Slot.TRINKET`, route to the two trinket bays.
Amulet gets a dedicated bay.

**Lockstep edit sites** (a missed one = item silently unequippable or never dropped):
`_natural_slot`, `InventoryUI` slot map, `LootService._roll_slot` (replace the contiguous range with a
`WEARABLE_SLOTS` const), `DungeonRun` loot path, affix `allowed_slots`.

**`weapon_class`** goes from dead to live. Whitelist: `sword, greatsword, dagger, axe, axe2h, mace,
hammer2h, spear, bow, crossbow, staff, wand, shield, tome`. Two consumers: `_sculpt_weapon` (visual)
and `_roll_base_id` (class filter).

---

## 3. Affixes, class stats & equip effects

**Class stats** to add to `StatBlock` (base-0 scalars; FLAT affixes work, INCREASED on base-0 = 0):
`spell_power, ranged_damage, holy, healing_power, shield, bleed_damage, dodge, penetration`
(`mana_max`, primaries, elementals, resistances already exist).

**Per-class stat map** (drives affix `class:<id>` tags; untagged = universal):
- **Warrior** — str, armor, crit_mult, bleed_damage, max_hp, rage_gen
- **Rogue** — dex, crit_chance, attack_speed, dodge, poison_damage, lifesteal
- **Mage** — int, mana_max, spell_power, cdr, fire/frost/lightning/dark_damage
- **Ranger** — dex, ranged_damage, penetration, crit_chance, move_speed
- **Paladin/Cleric** — armor, holy, healing_power, shield, max_hp, resistances

**Class restriction:** add `allowed_classes: Array[StringName] = []` to `ItemResource` (empty = any),
consumed in `_roll_base_id` vs `GameState.class_id` with an **unrestricted fallback** when the filtered
pool is empty (co-op group still sees drops). Definition-side, save-free.

**Biome theming:** patch `_affix_pool` to accept an affix when `a.biomes.has(biome)` OR `a.tags`
intersects the biome's `BiomeResource.affix_themes` (authored-but-dead — turn it on).

**Equip effects / procs** (the real mechanical gap — `StatModifier` has no trigger). New definition-side
`EffectResource`: `id, trigger{ON_HIT,ON_CRIT,ON_KILL,ON_HURT,ON_DASH,ON_EQUIP_AURA}, chance, cooldown,
magnitude, duration, radius, payload{frost_nova/burn/heal/multishot/dash_charge/aura_crit/earthquake},
tags`. Referenced from `ItemResource.equip_effects` (implicit) and `SetResource.procs`. A **host-only
`EffectComponent`** (sibling of `StatusEffectComponent`) subscribes to `DamageService.hit_resolved` +
`HealthComponent.died` + dash/hurt, gates on `has_state_authority`, rolls chance on `RNGService.combat`,
keeps cooldowns **in-memory only** (never in SaveData), and dispatches by payload to the existing
StatusEffect/Buff/Projectile/Ability systems. **Reference-by-id → zero new save bytes, zero determinism risk.**

---

## 4. Visible equipped models — the centerpiece

Today equipping changes stats only; the silhouette is built once at spawn and is 100% class-driven.
`item_equipped`/`item_unequipped` fire but **connect nowhere**. We fill that.

**`EquipmentVisualComponent`** (child of Player) owns `gear: Dictionary  # EquipSlot → MeshInstance3D`
and connects to the equip signals.

**Descriptor** (definition-side, save-free, on `ItemResource`): `visual_kind: StringName` (selects
`_sculpt_gear_<kind>`, ~16–20 routines), `visual_tint: Color` (0-alpha = inherit class palette),
`visual_glow: Color` (rarity drives intensity if unset). **We do NOT render `ItemResource.mesh`
PackedScenes** (at 100+ items: extra nodes, no batching, RAM at boot). ~16–20 procedural sculpts
parameterised by tint + rarity cover the whole catalog — *item count scales without asset count.*

**Slot → pivot → sculpt:** WEAPON→`_weapon` (kind from `weapon_class`); HELM→`_head`; CHEST→`_torso`
overlay; LEGS/BOOTS→`_leg_*_lo`; GLOVES→`_arm_*_lo` bracers; SHOULDERS→`_arm_*` pauldrons; CLOAK→`_cape`;
BELT→`_torso` waist; TRINKET/AMULET→emissive accent (reuse `_add_class_accent`).

**Rebuild-on-equip (incremental — the perf key):** on equip, resolve the pivot, free the prior slot
mesh, bake a new one via `VoxelModel.build_mesh` from `_sculpt_gear_<kind>(def, tint, glow)`, attach,
tint from `visual_tint`/class palette, emissive energy from the 7-tier rarity. **Only the affected
pivot rebuilds — never the whole character.** On unequip, free the slot mesh; weapon/helm fall back to
the class-cosmetic sculpt (so a bare character still looks right).

**Co-op replication (cosmetic, host-authoritative):** extend `PlayerNetSync` with a **reliable**
equipment channel (separate from the unreliable pos/yaw snapshot). Host broadcasts `slot→{base_id,rarity}`
on equip change *only*. Clients rebuild locally via the same component. Mirrors the trusted
`GameState.class_id` pattern. Never run gear RNG per-client.

---

## 5. Sets — 6 class sets

The engine is **already complete** for stat sets: `collect_modifiers` iterates `for threshold in
sdef.bonuses` cumulatively (2/4/6 are pure data); membership counts from `ItemInstance.set_id` then
`ItemResource.set_id`; bonuses recompute on equip and are never persisted. Missing: only 3 sets (2/4
only), no proc channel.

Planned sets (2/4/6, FLAT→INCREASED→MORE grammar; 6pc = a proc):

| Set | Class | 2pc | 4pc | 6pc proc (SHIPPED) |
|---|---|---|---|---|
| **Płomień Pustyni** `desert_flame` | Mage/fire | +15% fire dmg | +25% MORE fire | +20% MORE fire; ON_HIT 15% **fire-nova** |
| **Łowca Cieni** `shadow_hunter` | Rogue/Ranger | +0.08 crit chance | +1.0 crit_mult¹ | +0.05 crit; ON_CRIT **bleed-nova**² |
| **Mur Obrońcy** `wall_defender` | Warrior/Paladin | +20% armor | +20% MORE hp | +15% MORE armor; ON_HURT **shield-heal** <35% hp (8s cd) |
| **Gniew Gór** `mountain_wrath` | Warrior/Berserker | +8 bleed | +0.5 crit_mult | +15% MORE dmg; ON_HIT **earthquake** AoE (1.5s cd) |
| **Szept Mrozu** `frost_whisper` | Mage/Ranger | +8 frost | +30% atk-speed | +20% MORE frost; ON_KILL **frost-nova** |
| **Światło Przymierza** `covenant_light` | Paladin/Cleric | +12 healing | +15% hp | +8 holy; ON_EQUIP_AURA **party HoT** (6 hp/s, r8) |

¹ Old 4pc targeted `crit_damage` — a **dead stat** (combat reads `crit_mult`); fixed during the extend.
² Bible originally specced an atk-speed buff; the player has **no `BuffComponent`** (only Stats/Health/Status),
so a buff-dispatch path would ship unverified. Shadow Hunter instead procs a thematic crit-triggered bleed
AoE (`earthquake` payload). Re-add the haste buff when a player `BuffComponent` lands (separate follow-up).

Phase 5 (shipped) adds `procs: Dictionary{piece_count → Array[EffectResource]}` to `SetResource`, factors the
count loop into `active_set_thresholds()` (shared by stats + procs), wires set procs through `collect_effects()`,
and adds `get_active_set_bonuses()` for the UI. **`EffectComponent` gained three trigger rails:** the existing
hit bus (ON_HIT/ON_CRIT/ON_KILL) + a new **owner-damage bus** (`HealthComponent.damaged` → ON_HURT) + a
host-only **aura tick** (`_process` → ON_EQUIP_AURA periodic HoT over group `"player"`). New payloads:
`fire_nova` (fire AoE) and `shield` (defensive heal gated <35% hp). All host-authoritative, save-free.
**Sets ship with 6 reachable pieces each** (the 6pc proc is the capstone) — exceeds the ~4/set estimate in §7.

---

## 6. Loot tables & distribution

`drop_for(enemy)` is host-only; reads `loot_table/loot_ilvl/loot_biome/loot_tier_bonus`. Wire format
is the full `to_dict` so new fields round-trip free.

**Rarity by source:** trash = `DEFAULT_RARITY_WEIGHTS` + biome tier + magic-find (Mythic/Ancient
vanishingly rare); elite = shifted weights; dungeon TREASURE ≥ RARE, SECRET ≥ EPIC (keep); **boss** =
add `guaranteed_rarity` to `LootTableResource` (≥ LEGENDARY, chance SET/MYTHIC) + targeted boss-unique
+ set-token drops; **world-boss** (new entity) = dedicated table, `guaranteed_rarity ≥ MYTHIC`, a
**first-kill bonus** (guaranteed ANCIENT/set-token once per save). **This is where Mythic/Ancient live
in the economy.**

**Per-biome flavor:** forest nature/crit/mobility, snow cold, mountains armor/bleed/heavy, swamp poison,
desert fire/penetration, volcanic fire — via `affix_themes` + ~6–10 themed affixes/biome.

**Co-op/save:** definition-side fields round-trip free; the **only** new save field is a small set of
cleared world-boss ids in `SaveData` (default-empty get, still additive).

---

## 7. Content taxonomy — 131 items

| Category | Count | Breakdown |
|---|---|---|
| **Weapons** | 40 | sword 4, greatsword 3, dagger 3, axe 3, axe2h 3, mace 3, hammer2h 2, spear 3, bow 4, crossbow 3, staff 3, wand 3, shield 2, tome 1 |
| **Armor** | 45 | HELM 7, CHEST 8, LEGS 7, BOOTS 6, GLOVES 5, SHOULDERS 5, BELT 4, CLOAK 3 |
| **Accessories** | 12 | rings/charms (TRINKET) 8, AMULET 4 |
| **Set pieces** | 24 | 6 sets × ~4 pieces |
| **Consumables/materials** | 10 | potions, elixirs, materials, targeted drops |
| **TOTAL** | **131** | |

Plus ~90 affixes (21 existing + ~40 class + ~35 biome), 6 sets, ~20 effects.

**Authoring recipe:** promote `test/SeedData.gd._item` into a content-gen script that emits `.tres`
verbatim from a **flat table** (id, display_name, slot-int, weapon_class, visual_kind, implicit mods,
allowed_classes, set_id, req_level), organize into `data/db/items/{weapons,armor,accessories,sets,
consumables}/` subfolders (auto-scanned). **Ship a `ContentLint`** (boot/CI): duplicate-id, valid slot
int, `weapon_class` whitelist, non-dangling `set_id`, stat keys vs a central `STAT_KEYS` registry — the
`last-wins` silent collision is the #1 scale risk.

---

## Phased roadmap

| # | Phase | Deliverable | Verify |
|---|---|---|---|
| **1** | Foundation | 7-tier rarity (append Mythic/Ancient, grow arrays, decouple set, `>= LEGENDARY` unique) + slot/weapon_class expansion (append 5 slots, lockstep edits, `WEARABLE_SLOTS`) | save round-trip keeps old rarity/slot ints; per-slot equip routing; Mythic/Ancient reproduce from seed; Etap2/LootSet green |
| **2** | Class stats + affix pools | 8 StatBlock fields; `allowed_classes` + filter w/ fallback; biome `affix_themes`; pre-index ItemDB | nonzero get_stat per new stat; class-filtered drops; biome theme surfaces; no per-drop scan |
| **3** | **Visible equipped models** | `visual_*` fields; `EquipmentVisualComponent`; ~16–20 sculpts; incremental per-pivot bake; weapon/helm read equipped item | equip changes the pivot mesh w/o respawn; unequip reverts; only affected pivot rebuilt |
| **4** | Equip effects/procs | `EffectResource`; `equip_effects`; `collect_effects()`; host-only `EffectComponent`; generalize legendary unique | proc fires host-side w/ cooldown; no-op off-authority; no persisted proc state; determinism |
| **5** | Sets + set procs | 6 SetResource (extend 3 + add 3); `procs` map; `active_set_thresholds()`; UI accessor | 6pc cumulative stats; 6pc proc fires; ProcSetTest; save recomputes from pieces |
| **6** | Loot tables + world-boss + drop visuals | per-biome/dungeon/boss tables; `guaranteed_rarity`; world-boss + first-kill `SaveData` set; LootDrop 0..7 + particles | boss ≥ LEGENDARY; world-boss first-kill ANCIENT once; glow(ANCIENT)>glow(LEGENDARY) |
| **7** | Content-gen + lint + polish | content-gen script; 131-item / ~90-affix catalog; `ContentLint`; co-op equip replication; balance pass | lint green; client sees host's gear; balance-check OK; full suite green |

---

## Top risks

1. **Save corruption via enum reorder** → append-only + a pre-expansion-save regression.
2. **Co-op desync from RNG misuse** → fixed draw order; procs host-only on combat rng; two-peer determinism test.
3. **Missed lockstep slot edit** → single `WEARABLE_SLOTS` const + per-slot routing test.
4. **Perf regression on the visual track** → incremental per-pivot rebuild; code-gen meshes, never PackedScene; profile 4-player churn.
5. **Silent content bugs at 100+** → `ContentLint` + `STAT_KEYS` at boot.
6. **Set-vs-rarity ambiguity** → decouple (assign set when `set_id` non-empty) lands before set authoring.
7. **Effect cooldown/save coupling** → runtime state in-memory only; reference effects by id.
8. **Affix duplicate-stat starvation** → add the 8 class stats first so each class has ≥6 distinct rollable stats.

---

*Gear matters, looks powerful, and changes gameplay. Definition-side first, append-only, host-gated, incremental.*
