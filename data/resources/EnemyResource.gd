class_name EnemyResource
extends Resource
## EnemyResource.gd — definicja wroga (TDD 2.5). Etap 0: tylko schemat.
## stats: StatBlock skalowany per wariant (Brute/Slinger to te same eksporty).

@export var id: StringName = &""
@export var display_name: String = ""
@export var scene: PackedScene
@export var stats: StatBlock
@export var loot_table: LootTableResource
@export var xp_reward: int = 10
@export var ai_profile: StringName = &"melee"        # &"melee"/&"ranged"/&"caster"
@export var threat_tier: StringName = &"trash"       # &"trash"/&"elite"/&"boss" (telegraf — GDD 5.4)
@export var tameable: bool = false                   # pet od lvl 5
@export var tame_difficulty_mult: float = 1.0
@export var biomes: Array[StringName] = []
## ETAP 4: parametry wariantu spoza StatBlock (windup/zasięg/pocisk/skala/reskin/element).
## Czytane przez Enemy._apply_variant_meta. Klucze (wszystkie opcjonalne):
##   attack_windup, attack_range, attack_entry_delay, aggro_radius, leash_radius (float)
##   projectile_speed, projectile_gravity (float), projectile_pierce (int)
##   body_scale (float), element (StringName), skin_tint/eye_tint (Color)
@export var variant_meta: Dictionary = {}
